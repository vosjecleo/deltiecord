import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'public_network_address.dart';

/// Android UnifiedPush distributor state for one Matrix account registration.
final class UnifiedPushState {
  const UnifiedPushState({
    this.distributor,
    this.endpoint,
    this.error,
    this.lastMessageReceived,
    this.lastNotificationPosted,
    this.lastWorkerResult,
  });

  final String? distributor;
  final String? endpoint;
  final String? error;
  final DateTime? lastMessageReceived;
  final DateTime? lastNotificationPosted;
  final String? lastWorkerResult;

  bool get registered => endpoint?.isNotEmpty == true;
}

/// An installed external UnifiedPush distributor.
final class UnifiedPushDistributor {
  const UnifiedPushDistributor({
    required this.packageName,
    required this.label,
  });

  final String packageName;
  final String label;
}

/// Platform boundary for the official Android UnifiedPush connector.
///
/// External distributors such as ntfy return a private capability endpoint
/// through the Android connector protocol. Deltiecord never logs or exposes
/// that bearer capability.
final class UnifiedPushPlatform {
  UnifiedPushPlatform._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onStateChanged') return;
      final arguments = call.arguments;
      if (arguments is! Map) return;
      final instance = arguments['instance'];
      if (instance is String && instance.isNotEmpty) {
        _stateChanges.add(instance);
      }
    });
  }

  static final instance = UnifiedPushPlatform._();
  static const _channel = MethodChannel('net.deltie.deltiecord/unified_push');
  final StreamController<String> _stateChanges =
      StreamController<String>.broadcast();

  /// Account instances whose distributor endpoint changed asynchronously.
  ///
  /// UnifiedPush distributors may rotate an endpoint without a Settings
  /// action. The Matrix layer listens here and reconciles the corresponding
  /// pusher while the app is alive; cold-start reconciliation covers changes
  /// received while Flutter was stopped.
  Stream<String> get stateChanges => _stateChanges.stream;

  bool get supported =>
      defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  Future<List<UnifiedPushDistributor>> distributors() async {
    if (!supported) return const [];
    final result = await _channel.invokeListMethod<Object?>('getDistributors');
    return (result ?? const [])
        .whereType<Map>()
        .map((entry) {
          final packageName = '${entry['packageName'] ?? ''}'.trim();
          final label = '${entry['label'] ?? ''}'.trim();
          return UnifiedPushDistributor(
            packageName: packageName,
            label: label.isEmpty ? packageName : label,
          );
        })
        .where((entry) => entry.packageName.isNotEmpty)
        .toList(growable: false);
  }

  Future<UnifiedPushState> state(String instance) async {
    if (!supported) return const UnifiedPushState();
    final result = await _channel.invokeMapMethod<String, Object?>('getState', {
      'instance': instance,
    });
    return _decodeState(result);
  }

  Future<UnifiedPushState> selectDistributor(
    String distributor,
    String instance,
  ) => _invokeRegistration('selectDistributor', {
    'distributor': distributor,
    'instance': instance,
  }, instance);

  Future<UnifiedPushState> register(String instance) =>
      _invokeRegistration('register', {'instance': instance}, instance);

  Future<void> unregister(String instance) =>
      _channel.invokeMethod<void>('unregister', {'instance': instance});

  /// Selects a known external distributor on a fresh installation.
  ///
  /// An existing choice is never replaced. Deltiecord deliberately does not
  /// auto-select its own package: embedded WebPush requires a configured VAPID
  /// gateway and cannot share the ntfy Matrix gateway contract.
  Future<bool> ensureDefaultDistributor(String instance) async {
    if (!supported) return false;
    final current = await state(instance);
    if (current.distributor?.isNotEmpty == true) return false;
    final available = await distributors();
    if (available.isEmpty) return false;
    const preferredPackages = ['io.heckel.ntfy', 'foundation.e.ntfy'];
    final preferred = available.where(
      (entry) => preferredPackages.contains(entry.packageName),
    );
    final selected = preferred.firstOrNull ?? available.first;
    await selectDistributor(selected.packageName, instance);
    return true;
  }

  /// Waits for the distributor's asynchronous endpoint callback.
  ///
  /// The periodic state read is intentional. Android can deliver the callback
  /// while Flutter is paused, in which case the endpoint is persisted by the
  /// native service but the method-channel notification is missed.
  Future<UnifiedPushState> waitForEndpoint(
    String instance, {
    UnifiedPushState? initialState,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    var latest = initialState ?? await state(instance);
    if (latest.registered || latest.error != null) return latest;

    final completer = Completer<UnifiedPushState>();
    Timer? poll;
    Timer? deadline;
    StreamSubscription<String>? subscription;

    Future<void> refresh() async {
      if (completer.isCompleted) return;
      latest = await state(instance);
      if (latest.registered || latest.error != null) {
        completer.complete(latest);
      }
    }

    subscription = stateChanges
        .where((value) => value == instance)
        .listen((_) => unawaited(refresh()));
    poll = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(refresh()),
    );
    deadline = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(latest);
    });
    unawaited(refresh());
    try {
      return await completer.future;
    } finally {
      poll.cancel();
      deadline.cancel();
      await subscription.cancel();
    }
  }

  UnifiedPushState _decodeState(Map<String, Object?>? result) =>
      UnifiedPushState(
        distributor: result?['distributor'] as String?,
        endpoint: result?['endpoint'] as String?,
        error: result?['error'] as String?,
        lastMessageReceived: _dateFromMilliseconds(
          result?['lastMessageReceived'],
        ),
        lastNotificationPosted: _dateFromMilliseconds(
          result?['lastNotificationPosted'],
        ),
        lastWorkerResult: result?['lastWorkerResult'] as String?,
      );

  DateTime? _dateFromMilliseconds(Object? value) {
    final milliseconds = int.tryParse('$value');
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  Future<UnifiedPushState> _invokeRegistration(
    String method,
    Map<String, String> arguments,
    String instance,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      return _decodeState(result);
    } on PlatformException {
      // A distributor callback can race the native registration timeout. The
      // callback-owned preference is authoritative, so recover it before
      // reporting a failure that would otherwise disappear after restart.
      final recovered = await state(instance);
      if (recovered.registered) return recovered;
      rethrow;
    }
  }
}

/// Validates and normalizes the private capability URL returned by ntfy.
///
/// The opaque path and query are deliberately not inspected or logged. The
/// server enforces its high-entropy `up*` topic ACL; the client only needs to
/// ensure the bearer capability cannot be redirected to another origin.
String? normalizeUnifiedPushEndpoint(String value) {
  var normalized = value
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f\u200b\ufeff]'), '')
      .trim();
  if (normalized.length >= 2 &&
      ((normalized.startsWith('"') && normalized.endsWith('"')) ||
          (normalized.startsWith("'") && normalized.endsWith("'")))) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  if (normalized.toLowerCase().startsWith('push.deltie.net/')) {
    normalized = 'https://$normalized';
  }
  var uri = Uri.tryParse(normalized);
  // Older ntfy Android configurations may report this custom origin as HTTP.
  // Upgrade only Deltiecord's fixed, TLS-backed push host; arbitrary origins
  // are never rewritten or accepted.
  if (uri != null &&
      uri.scheme.toLowerCase() == 'http' &&
      uri.host.toLowerCase() == 'push.deltie.net' &&
      (!uri.hasPort || uri.port == 80) &&
      uri.userInfo.isEmpty) {
    uri = Uri.parse(
      'https://push.deltie.net${uri.path}'
      '${uri.hasQuery ? '?${uri.query}' : ''}',
    );
  }
  // URI fragments are local-only and are never sent to ntfy. Some distributor
  // versions append connector metadata there; strip it instead of rejecting an
  // otherwise valid private push capability.
  if (uri != null && uri.fragment.isNotEmpty) {
    uri = Uri.tryParse(uri.toString().split('#').first);
  }
  final literalAddress = uri == null
      ? null
      : InternetAddress.tryParse(uri.host);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      (uri.hasPort && uri.port != 443) ||
      uri.host.toLowerCase() == 'localhost' ||
      (literalAddress != null && !isPublicInternetAddress(literalAddress)) ||
      uri.userInfo.isNotEmpty ||
      uri.pathSegments.where((part) => part.isNotEmpty).isEmpty) {
    return null;
  }
  return uri.toString();
}

/// Returns the Matrix push gateway belonging to a UnifiedPush endpoint.
///
/// An ntfy capability is only meaningful to the ntfy server that issued it.
/// Sending an `ntfy.sh` capability to Deltiecord's private ntfy gateway makes
/// the gateway reject the device and causes the homeserver to delete its
/// pusher. Keep the opaque capability and its Matrix gateway on one origin.
Uri? matrixPushGatewayForUnifiedPushEndpoint(String value) {
  final normalized = normalizeUnifiedPushEndpoint(value);
  final endpoint = normalized == null ? null : Uri.tryParse(normalized);
  if (endpoint == null) return null;
  return Uri(
    scheme: endpoint.scheme,
    host: endpoint.host,
    port: endpoint.hasPort ? endpoint.port : null,
    path: '/_matrix/push/v1/notify',
  );
}
