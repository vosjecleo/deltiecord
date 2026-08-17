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
  UnifiedPushPlatform._();

  static final instance = UnifiedPushPlatform._();
  static const _channel = MethodChannel('net.deltie.deltiecord/unified_push');

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
    return UnifiedPushState(
      distributor: result?['distributor'] as String?,
      endpoint: result?['endpoint'] as String?,
      error: result?['error'] as String?,
    );
  }

  Future<void> selectDistributor(String distributor, String instance) =>
      _channel.invokeMethod<void>('selectDistributor', {
        'distributor': distributor,
        'instance': instance,
      });

  Future<void> register(String instance) =>
      _channel.invokeMethod<void>('register', {'instance': instance});

  Future<void> unregister(String instance) =>
      _channel.invokeMethod<void>('unregister', {'instance': instance});
}
