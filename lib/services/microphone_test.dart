import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// Parameters used to open an isolated microphone-test capture session.
final class MicrophoneTestConfiguration {
  const MicrophoneTestConfiguration({
    this.deviceId,
    required this.echoCancellation,
    required this.noiseSuppression,
    required this.autoGainControl,
  });

  final String? deviceId;
  final bool echoCancellation;
  final bool noiseSuppression;
  final bool autoGainControl;
}

abstract interface class MicrophoneTestSession {
  Stream<double> get levels;

  Future<void> setListening(bool enabled);

  Future<void> dispose();
}

abstract interface class MicrophoneTestPlatform {
  Future<MicrophoneTestSession> start(MicrophoneTestConfiguration config);
}

/// UI-safe owner for a native microphone-test session.
///
/// The controller always disposes the previous session before opening another
/// and is itself disposed with Settings. Native WebRTC objects never cross
/// this service boundary.
final class MicrophoneTestController extends ChangeNotifier {
  MicrophoneTestController({MicrophoneTestPlatform? platform})
    : _platform = platform ?? WebRtcMicrophoneTestPlatform();

  final MicrophoneTestPlatform _platform;
  MicrophoneTestSession? _session;
  StreamSubscription<double>? _levelSubscription;
  bool _starting = false;
  bool _listening = false;
  bool _disposed = false;
  double _level = 0;
  String? _error;

  bool get running => _session != null;
  bool get starting => _starting;
  bool get listening => _listening;
  double get level => _level;
  String? get error => _error;

  Future<void> start(MicrophoneTestConfiguration configuration) async {
    if (_starting || _disposed) return;
    _starting = true;
    _error = null;
    notifyListeners();
    await stop();
    try {
      final session = await _platform.start(configuration);
      if (_disposed) {
        await session.dispose();
        return;
      }
      _session = session;
      _levelSubscription = session.levels.listen((value) {
        if (_disposed) return;
        _level = value.clamp(0, 1);
        notifyListeners();
      });
    } catch (exception) {
      _error = 'Microphone test could not start: $exception';
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setListening(bool enabled) async {
    final session = _session;
    if (session == null || _disposed) return;
    try {
      await session.setListening(enabled);
      _listening = enabled;
      _error = null;
    } catch (exception) {
      _error = 'Local microphone playback is unavailable: $exception';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    _listening = false;
    _level = 0;
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    final session = _session;
    _session = null;
    await session?.dispose();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

/// Native WebRTC loopback used for metering and optional local monitoring.
final class WebRtcMicrophoneTestPlatform implements MicrophoneTestPlatform {
  @override
  Future<MicrophoneTestSession> start(MicrophoneTestConfiguration config) =>
      _WebRtcMicrophoneTestSession.open(config);
}

final class _WebRtcMicrophoneTestSession implements MicrophoneTestSession {
  _WebRtcMicrophoneTestSession._();

  final _levelController = StreamController<double>.broadcast();
  webrtc.MediaStream? _localStream;
  webrtc.RTCPeerConnection? _sender;
  webrtc.RTCPeerConnection? _receiver;
  webrtc.MediaStreamTrack? _monitorTrack;
  Timer? _meterTimer;
  bool _sampling = false;
  bool _disposed = false;

  static Future<_WebRtcMicrophoneTestSession> open(
    MicrophoneTestConfiguration config,
  ) async {
    final session = _WebRtcMicrophoneTestSession._();
    try {
      await session._initialize(config);
      return session;
    } catch (_) {
      await session.dispose();
      rethrow;
    }
  }

  Future<void> _initialize(MicrophoneTestConfiguration config) async {
    _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': config.echoCancellation,
        'noiseSuppression': config.noiseSuppression,
        'autoGainControl': config.autoGainControl,
        if (config.deviceId != null) 'deviceId': {'exact': config.deviceId},
      },
      'video': false,
    });
    _sender = await webrtc.createPeerConnection({
      'sdpSemantics': 'unified-plan',
    });
    for (final track in _localStream!.getAudioTracks()) {
      await _sender!.addTrack(track, _localStream!);
    }

    // Android's WebRTC backend has crashed in the native loopback/volume path
    // on several devices. A sender-only peer connection still exposes the
    // media-source audio level and is sufficient for a safe microphone test.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final offer = await _sender!.createOffer();
      await _sender!.setLocalDescription(offer);
      _meterTimer = Timer.periodic(
        const Duration(milliseconds: 140),
        (_) => unawaited(_sampleLevel()),
      );
      return;
    }

    _receiver = await webrtc.createPeerConnection({
      'sdpSemantics': 'unified-plan',
    });
    _sender!.onIceCandidate = (candidate) {
      if (!_disposed) unawaited(_receiver!.addCandidate(candidate));
    };
    _receiver!.onIceCandidate = (candidate) {
      if (!_disposed) unawaited(_sender!.addCandidate(candidate));
    };
    _receiver!.onTrack = (event) {
      if (_disposed || event.track.kind != 'audio') return;
      _monitorTrack = event.track;
      event.track.enabled = false;
      unawaited(webrtc.Helper.setVolume(0, event.track));
    };

    final offer = await _sender!.createOffer();
    await _sender!.setLocalDescription(offer);
    await _receiver!.setRemoteDescription(offer);
    final answer = await _receiver!.createAnswer();
    await _receiver!.setLocalDescription(answer);
    await _sender!.setRemoteDescription(answer);
    _meterTimer = Timer.periodic(
      const Duration(milliseconds: 140),
      (_) => unawaited(_sampleLevel()),
    );
  }

  Future<void> _sampleLevel() async {
    final sender = _sender;
    if (_disposed || _sampling || sender == null) return;
    _sampling = true;
    var level = 0.0;
    try {
      for (final report in await sender.getStats()) {
        if (report.type != 'media-source' || report.values['kind'] != 'audio') {
          continue;
        }
        final sample = report.values['audioLevel'];
        if (sample is num) level = max(level, sample.toDouble());
      }
    } finally {
      _sampling = false;
    }
    if (!_disposed) _levelController.add(level.clamp(0, 1));
  }

  @override
  Stream<double> get levels => _levelController.stream;

  @override
  Future<void> setListening(bool enabled) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      throw UnsupportedError(
        'Local microphone monitoring is unavailable on Android. The live '
        'level meter remains active.',
      );
    }
    final track = _monitorTrack;
    if (track == null) {
      throw StateError('Microphone monitor track is not ready.');
    }
    track.enabled = enabled;
    await webrtc.Helper.setVolume(enabled ? 1 : 0, track);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _meterTimer?.cancel();
    _meterTimer = null;
    for (final track in _localStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _sender?.close();
    await _sender?.dispose();
    _sender = null;
    await _receiver?.close();
    await _receiver?.dispose();
    _receiver = null;
    _monitorTrack = null;
    await _levelController.close();
  }
}
