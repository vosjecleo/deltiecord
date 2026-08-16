import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:matrix/matrix.dart';

import '../models/chat_models.dart';
import '../services/app_sounds.dart';
import 'deltiecord_webrtc_delegate.dart';

/// Owns MatrixRTC/WebRTC resources independently from session and timeline
/// state. This uses matrix-dart-sdk's MatrixRTC model and flutter-webrtc's
/// native bindings; see CREDITS.md. Exactly one call may be active at a time.
class MatrixVoiceController extends ChangeNotifier {
  MatrixVoiceController(this._client, {required this.friendlyError});

  final Client _client;
  final String Function(Object error) friendlyError;
  VoIP? _voip;
  GroupCallSession? _activeCall;
  StreamSubscription<MatrixRTCCallEvent>? _callSubscription;
  VoiceConnectionStatus _status = VoiceConnectionStatus.disconnected;
  bool _muted = false;
  bool _deafened = false;
  bool _cameraEnabled = false;
  bool _screenSharing = false;
  String? _error;
  String? _activeSpeakerUserId;
  List<AudioInputSummary> _audioInputs = const [];
  String? _selectedAudioInputId;
  List<RtcDeviceSummary> _audioOutputs = const [];
  String? _selectedAudioOutputId;
  List<RtcDeviceSummary> _cameras = const [];
  String? _selectedCameraId;
  final Map<String, double> _participantVolumes = {};
  final Set<String> _locallyMutedParticipants = {};
  Timer? _inputMeterTimer;
  double _inputLevel = 0;
  bool _samplingInput = false;
  bool _rejoining = false;
  bool _disposed = false;
  bool _echoCancellation = true;
  bool _noiseSuppression = true;
  bool _autoGainControl = true;
  double _microphoneVolume = 1;
  double _outputVolume = 1;
  bool _callSound = true;

  VoiceConnectionStatus get status => _status;
  String? get activeRoomId => _activeCall?.room.id;
  bool get muted => _muted;
  bool get deafened => _deafened;
  bool get cameraEnabled => _cameraEnabled;
  bool get screenSharing => _screenSharing;
  double get inputLevel => _muted ? 0 : _inputLevel;
  String? get error => _error;
  String? get activeSpeakerUserId => _activeSpeakerUserId;
  List<AudioInputSummary> get audioInputs => _audioInputs;
  String? get selectedAudioInputId => _selectedAudioInputId;
  List<RtcDeviceSummary> get audioOutputs => _audioOutputs;
  String? get selectedAudioOutputId => _selectedAudioOutputId;
  List<RtcDeviceSummary> get cameras => _cameras;
  String? get selectedCameraId => _selectedCameraId;

  List<RtcMediaStreamSummary> get mediaStreams {
    final call = _activeCall;
    if (call == null) return const [];
    final streams = [
      ...call.backend.userMediaStreams.map((stream) => (stream, false)),
      ...call.backend.screenShareStreams.map((stream) => (stream, true)),
    ];
    return streams
        .where(
          (entry) =>
              entry.$1.stream != null &&
              entry.$1.stream!.getVideoTracks().isNotEmpty,
        )
        .map(
          (entry) => RtcMediaStreamSummary(
            id: entry.$1.id,
            userId: entry.$1.participant.userId,
            displayName: entry.$1.displayName ?? entry.$1.participant.userId,
            stream: entry.$1.stream!,
            local: entry.$1.isLocal(),
            screenShare: entry.$2,
            videoMuted: entry.$1.isVideoMuted(),
          ),
        )
        .toList(growable: false);
  }

  double participantVolume(String userId) => _participantVolumes[userId] ?? 1;

  bool participantLocallyMuted(String userId) =>
      _locallyMutedParticipants.contains(userId);

  void applyPreferences(AppPreferences preferences) {
    final processingChanged =
        _echoCancellation != preferences.echoCancellation ||
        _noiseSuppression != preferences.noiseSuppression ||
        _autoGainControl != preferences.autoGainControl;
    _echoCancellation = preferences.echoCancellation;
    _noiseSuppression = preferences.noiseSuppression;
    _autoGainControl = preferences.autoGainControl;
    _microphoneVolume = preferences.microphoneVolume.clamp(0, 1);
    _outputVolume = preferences.outputVolume.clamp(0, 1);
    _callSound = preferences.callSound;
    final inputId = preferences.preferredAudioInputId;
    final outputId = preferences.preferredAudioOutputId;
    final cameraId = preferences.preferredCameraId;
    _selectedAudioInputId =
        inputId.isEmpty ||
            (_audioInputs.isNotEmpty &&
                !_audioInputs.any((device) => device.id == inputId))
        ? null
        : inputId;
    _selectedAudioOutputId =
        outputId.isEmpty ||
            (_audioOutputs.isNotEmpty &&
                !_audioOutputs.any((device) => device.id == outputId))
        ? null
        : outputId;
    _selectedCameraId =
        cameraId.isEmpty ||
            (_cameras.isNotEmpty &&
                !_cameras.any((device) => device.id == cameraId))
        ? null
        : cameraId;
    _participantVolumes
      ..clear()
      ..addAll(preferences.participantVolumes);
    final selectedOutputId = _selectedAudioOutputId;
    if (selectedOutputId != null) {
      unawaited(
        flutter_webrtc.Helper.selectAudioOutput(
          selectedOutputId,
        ).catchError((_) {}),
      );
    }
    unawaited(_applyRemoteAudioSettings());
    unawaited(_applyLocalInputVolume());
    final roomId = activeRoomId;
    if (processingChanged && roomId != null) {
      unawaited(_rejoinPreservingState(roomId));
    }
    notifyListeners();
  }

  void initialize() {
    if (!_client.isLogged() || _voip != null || _disposed) return;
    _voip = VoIP(
      _client,
      DeltiecordWebRtcDelegate(
        isCallActive: () =>
            _status == VoiceConnectionStatus.connecting ||
            _status == VoiceConnectionStatus.reconnecting ||
            _status == VoiceConnectionStatus.connected,
      ),
    );
    unawaited(refreshAudioInputs());
  }

  Future<void> refreshAudioInputs() async {
    var inputDisappeared = false;
    var cameraDisappeared = false;
    try {
      final devices = await flutter_webrtc.navigator.mediaDevices
          .enumerateDevices();
      if (_disposed) return;
      _audioInputs = devices
          .where((device) => device.kind == 'audioinput')
          .map(
            (device) => AudioInputSummary(
              id: device.deviceId,
              label: device.label.isEmpty ? 'Microphone' : device.label,
            ),
          )
          .toList(growable: false);
      _audioOutputs = devices
          .where((device) => device.kind == 'audiooutput')
          .map(
            (device) => RtcDeviceSummary(
              id: device.deviceId,
              label: device.label.isEmpty ? 'Audio output' : device.label,
            ),
          )
          .toList(growable: false);
      _cameras = devices
          .where((device) => device.kind == 'videoinput')
          .map(
            (device) => RtcDeviceSummary(
              id: device.deviceId,
              label: device.label.isEmpty ? 'Camera' : device.label,
            ),
          )
          .toList(growable: false);
      if (_selectedAudioInputId != null &&
          !_audioInputs.any((input) => input.id == _selectedAudioInputId)) {
        inputDisappeared = true;
        _selectedAudioInputId = null;
      }
      if (_selectedAudioOutputId != null &&
          !_audioOutputs.any((output) => output.id == _selectedAudioOutputId)) {
        _selectedAudioOutputId = null;
      }
      if (_selectedCameraId != null &&
          !_cameras.any((camera) => camera.id == _selectedCameraId)) {
        cameraDisappeared = true;
        _selectedCameraId = null;
      }
    } catch (_) {
      if (_disposed) return;
      _audioInputs = const [];
      _audioOutputs = const [];
      _cameras = const [];
    }
    notifyListeners();
    final roomId = activeRoomId;
    if (roomId != null && (inputDisappeared || cameraDisappeared)) {
      _error = cameraDisappeared && _cameraEnabled
          ? 'The selected camera disappeared; reconnecting with a fallback.'
          : 'The selected audio device disappeared; reconnecting.';
      unawaited(_rejoinPreservingState(roomId));
    }
  }

  Future<void> selectAudioOutput(String? deviceId) async {
    if (_disposed || _selectedAudioOutputId == deviceId) return;
    try {
      if (deviceId != null) {
        await flutter_webrtc.Helper.selectAudioOutput(deviceId);
      }
      _selectedAudioOutputId = deviceId;
      _error = null;
    } catch (exception) {
      _error = friendlyError(exception);
    }
    notifyListeners();
  }

  Future<void> selectCamera(String? deviceId) async {
    if (_disposed || _selectedCameraId == deviceId) return;
    _selectedCameraId = deviceId;
    final roomId = activeRoomId;
    notifyListeners();
    if (roomId != null && _cameraEnabled) {
      await _rejoinPreservingState(roomId);
    }
  }

  Future<void> selectAudioInput(String? deviceId) async {
    if (_selectedAudioInputId == deviceId || _disposed) return;
    final reconnectRoomId = activeRoomId;
    _selectedAudioInputId = deviceId;
    notifyListeners();
    if (reconnectRoomId != null) {
      await _rejoinPreservingState(reconnectRoomId);
    }
  }

  Future<void> join(String roomId) async {
    if (_disposed ||
        (activeRoomId == roomId &&
            _status == VoiceConnectionStatus.connected)) {
      return;
    }
    if (_activeCall != null) await leave();
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    initialize();
    final voip = _voip;
    if (voip == null) return;
    _status = _rejoining
        ? VoiceConnectionStatus.reconnecting
        : VoiceConnectionStatus.connecting;
    _error = null;
    notifyListeners();
    GroupCallSession? joiningCall;
    try {
      final call = joiningCall = await voip.fetchOrCreateGroupCall(
        room.id,
        room,
        MeshBackend(),
        'm.call',
        'm.room',
      );
      if (_disposed) return;
      _activeCall = call;
      await _callSubscription?.cancel();
      _callSubscription = call.matrixRTCEventStream.stream.listen(
        _handleCallEvent,
      );
      final audioConstraints = <String, dynamic>{
        'echoCancellation': _echoCancellation,
        'noiseSuppression': _noiseSuppression,
        'autoGainControl': _autoGainControl,
        'volume': _microphoneVolume,
        if (_selectedAudioInputId != null)
          'deviceId': {'exact': _selectedAudioInputId},
      };
      flutter_webrtc.MediaStream stream;
      try {
        stream = await flutter_webrtc.navigator.mediaDevices.getUserMedia({
          'audio': audioConstraints,
          'video': _cameraEnabled
              ? {
                  'width': {'ideal': 1280},
                  'height': {'ideal': 720},
                  if (_selectedCameraId != null)
                    'deviceId': {'exact': _selectedCameraId},
                }
              : false,
        });
      } catch (exception) {
        if (!_cameraEnabled) rethrow;
        _cameraEnabled = false;
        _error = 'Camera unavailable; joined with audio only.';
        stream = await flutter_webrtc.navigator.mediaDevices.getUserMedia({
          'audio': audioConstraints,
          'video': false,
        });
      }
      if (_disposed || !identical(call, _activeCall)) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        return;
      }
      await call.enter(
        stream: WrappedMediaStream(
          stream: stream,
          participant: call.localParticipant!,
          room: room,
          client: _client,
          purpose: SDPStreamMetadataPurpose.Usermedia,
          audioMuted: _muted,
          videoMuted: !_cameraEnabled,
          isGroupCall: true,
          voip: voip,
        ),
      );
      _status = VoiceConnectionStatus.connected;
      if (_muted) {
        await call.backend.setDeviceMuted(
          call,
          true,
          MediaInputKind.audioinput,
        );
      }
      _startInputMeter();
      await _applyLocalInputVolume();
      await _applyRemoteAudioSettings();
      if (_callSound && !_rejoining) unawaited(AppSounds.callConnected());
    } catch (exception) {
      try {
        await joiningCall?.leave();
      } catch (_) {
        try {
          if (joiningCall != null) {
            await joiningCall.backend.dispose(joiningCall);
          }
        } catch (_) {}
      }
      _status = VoiceConnectionStatus.error;
      _error = friendlyError(exception);
      _activeCall = null;
    }
    if (!_disposed) notifyListeners();
  }

  void _startInputMeter() {
    _inputMeterTimer?.cancel();
    _inputMeterTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => unawaited(_sampleInputLevel()),
    );
  }

  Future<void> _sampleInputLevel() async {
    final call = _activeCall;
    if (call == null || _samplingInput || _disposed || _muted) {
      if (_inputLevel != 0) {
        _inputLevel = 0;
        if (!_disposed) notifyListeners();
      }
      return;
    }
    _samplingInput = true;
    var sampled = 0.0;
    try {
      for (final wrapped in call.backend.userMediaStreams) {
        final peerConnection = wrapped.pc;
        if (peerConnection == null) continue;
        final reports = await peerConnection.getStats();
        for (final report in reports) {
          if (report.type != 'media-source' ||
              report.values['kind'] != 'audio') {
            continue;
          }
          final level = report.values['audioLevel'];
          if (level is num) sampled = max(sampled, level.toDouble());
        }
      }
    } catch (_) {
      // WebRTC stats availability varies by Linux backend.
    } finally {
      _samplingInput = false;
    }
    if ((_inputLevel - sampled).abs() >= 0.01) {
      _inputLevel = sampled.clamp(0, 1);
      if (!_disposed) notifyListeners();
    }
  }

  void _handleCallEvent(MatrixRTCCallEvent event) {
    if (_disposed) return;
    switch (event) {
      case GroupCallStateChanged(:final state):
        _status = switch (state) {
          GroupCallState.entered => VoiceConnectionStatus.connected,
          GroupCallState.entering ||
          GroupCallState.initializingLocalCallFeed ||
          GroupCallState.localCallFeedInitialized =>
            _rejoining
                ? VoiceConnectionStatus.reconnecting
                : VoiceConnectionStatus.connecting,
          GroupCallState.leaving =>
            _rejoining
                ? VoiceConnectionStatus.reconnecting
                : VoiceConnectionStatus.disconnecting,
          GroupCallState.ended || GroupCallState.localCallFeedUninitialized =>
            VoiceConnectionStatus.disconnected,
        };
      case GroupCallStateError(:final msg):
        _status = _activeCall?.state == GroupCallState.entered
            ? VoiceConnectionStatus.connected
            : VoiceConnectionStatus.error;
        _error = msg;
      case GroupCallLocalMutedChanged(:final muted, :final kind):
        if (kind == MediaInputKind.audioinput) _muted = muted;
        if (kind == MediaInputKind.videoinput) _cameraEnabled = !muted;
      case GroupCallActiveSpeakerChanged(:final participant):
        _activeSpeakerUserId = participant.userId;
      case GroupCallLocalScreenshareStateChanged(:final screensharing):
        _screenSharing = screensharing;
      case GroupCallStreamAdded() ||
          GroupCallStreamRemoved() ||
          GroupCallStreamReplaced():
        unawaited(_applyRemoteAudioSettings());
      default:
        break;
    }
    notifyListeners();
  }

  Future<void> setDeafened(bool deafened) async {
    if (_deafened == deafened || _disposed) return;
    _deafened = deafened;
    await _applyRemoteAudioSettings();
    notifyListeners();
  }

  Future<void> setParticipantVolume(String userId, double volume) async {
    _participantVolumes[userId] = volume.clamp(0, 1);
    await _applyRemoteAudioSettings(userId: userId);
    notifyListeners();
  }

  Future<void> setParticipantLocallyMuted(String userId, bool muted) async {
    if (muted) {
      _locallyMutedParticipants.add(userId);
    } else {
      _locallyMutedParticipants.remove(userId);
    }
    await _applyRemoteAudioSettings(userId: userId);
    notifyListeners();
  }

  Future<void> _applyRemoteAudioSettings({String? userId}) async {
    final call = _activeCall;
    if (call == null) return;
    for (final wrapped in call.backend.userMediaStreams) {
      if (wrapped.isLocal() ||
          (userId != null && wrapped.participant.userId != userId)) {
        continue;
      }
      final volume =
          _deafened ||
              _locallyMutedParticipants.contains(wrapped.participant.userId)
          ? 0.0
          : participantVolume(wrapped.participant.userId) * _outputVolume;
      for (final track in wrapped.stream?.getAudioTracks() ?? const []) {
        try {
          await flutter_webrtc.Helper.setVolume(volume, track);
        } catch (_) {
          // Some Linux audio backends do not expose per-track volume.
        }
      }
    }
  }

  Future<void> _applyLocalInputVolume() async {
    final call = _activeCall;
    if (call == null) return;
    for (final wrapped in call.backend.userMediaStreams.where(
      (stream) => stream.isLocal(),
    )) {
      for (final track in wrapped.stream?.getAudioTracks() ?? const []) {
        try {
          await flutter_webrtc.Helper.setVolume(_microphoneVolume, track);
        } catch (_) {
          // Some Linux capture backends expose processing but not gain.
        }
      }
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (_disposed || _cameraEnabled == enabled) return;
    _cameraEnabled = enabled;
    final roomId = activeRoomId;
    notifyListeners();
    if (roomId != null) {
      await _rejoinPreservingState(roomId);
    }
  }

  Future<void> _rejoinPreservingState(String roomId) async {
    if (_rejoining || _disposed) return;
    _rejoining = true;
    _status = VoiceConnectionStatus.reconnecting;
    notifyListeners();
    final wasMuted = _muted;
    final wasDeafened = _deafened;
    try {
      await leave();
      await join(roomId);
      if (_status == VoiceConnectionStatus.connected) {
        if (wasMuted) await setMuted(true);
        if (wasDeafened) await setDeafened(true);
      }
    } finally {
      _rejoining = false;
    }
  }

  Future<void> setScreenSharing(bool enabled) async {
    final call = _activeCall;
    if (call == null || _disposed || _screenSharing == enabled) return;
    _error = null;
    try {
      await call.backend.setScreensharingEnabled(call, enabled, '');
      _screenSharing = call.backend.localScreenshareStream != null;
    } catch (exception) {
      _error = friendlyError(exception);
      _screenSharing = call.backend.localScreenshareStream != null;
    }
    notifyListeners();
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    _muted = muted;
    notifyListeners();
    final call = _activeCall;
    if (call == null) return;
    try {
      await call.backend.setDeviceMuted(call, muted, MediaInputKind.audioinput);
    } catch (exception) {
      _error = friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> leave() async {
    final call = _activeCall;
    if (call == null) return;
    _status = _rejoining
        ? VoiceConnectionStatus.reconnecting
        : VoiceConnectionStatus.disconnecting;
    if (!_disposed) notifyListeners();
    final playDisconnectSound = _callSound && !_rejoining && !_disposed;
    try {
      await call.leave();
    } finally {
      _inputMeterTimer?.cancel();
      _inputMeterTimer = null;
      _inputLevel = 0;
      await _callSubscription?.cancel();
      _callSubscription = null;
      _activeCall = null;
      _activeSpeakerUserId = null;
      _screenSharing = false;
      _status = _rejoining
          ? VoiceConnectionStatus.reconnecting
          : VoiceConnectionStatus.disconnected;
      if (!_disposed) notifyListeners();
      if (playDisconnectSound) unawaited(AppSounds.callDisconnected());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _inputMeterTimer?.cancel();
    unawaited(leave());
    super.dispose();
  }
}
