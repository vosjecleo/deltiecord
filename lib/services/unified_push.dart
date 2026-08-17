import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android UnifiedPush distributor state for one Matrix account registration.
final class UnifiedPushState {
  const UnifiedPushState({this.distributor, this.endpoint, this.error});

  final String? distributor;
  final String? endpoint;
  final String? error;

  bool get registered => endpoint?.isNotEmpty == true;
}

/// Platform boundary for the official Android UnifiedPush connector.
///
/// Deltiecord never embeds distributor credentials. Users configure an ntfy
/// distributor app, which returns a private capability endpoint through the
/// Android connector protocol.
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

  Future<List<String>> distributors() async {
    if (!supported) return const [];
    final result = await _channel.invokeListMethod<String>('getDistributors');
    return result ?? const [];
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

  /// Selects the first installed distributor on a fresh installation.
  ///
  /// An existing choice is never replaced. Distributor ordering is owned by
  /// Android, so the first entry is the platform's preferred/default choice.
  Future<bool> ensureDefaultDistributor(String instance) async {
    if (!supported) return false;
    final current = await state(instance);
    if (current.distributor?.isNotEmpty == true) return false;
    final available = await distributors();
    if (available.isEmpty) return false;
    await selectDistributor(available.first, instance);
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
      );

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
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.toLowerCase() != 'push.deltie.net' ||
      (uri.hasPort && uri.port != 443) ||
      uri.userInfo.isNotEmpty ||
      uri.pathSegments.where((part) => part.isNotEmpty).isEmpty) {
    return null;
  }
  return uri.toString();
}
