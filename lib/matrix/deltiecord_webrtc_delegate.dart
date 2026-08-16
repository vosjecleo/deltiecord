import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

/// Supplies the Matrix SDK with flutter_webrtc primitives.
///
/// Call presentation remains in the application layer. The delegate deliberately
/// has no UI side effects, which also makes it reusable by the future Android UI.
class DeltiecordWebRtcDelegate implements WebRTCDelegate {
  DeltiecordWebRtcDelegate({
    required this.isCallActive,
    required this.shareDesktopAudio,
  }) : _mediaDevices = _DeltiecordMediaDevices(
         flutter_webrtc.navigator.mediaDevices,
         shareDesktopAudio,
       );

  final bool Function() isCallActive;
  final bool Function() shareDesktopAudio;
  final MediaDevices _mediaDevices;

  @override
  MediaDevices get mediaDevices => _mediaDevices;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) => flutter_webrtc.createPeerConnection(configuration, constraints);

  @override
  bool get isWeb => false;

  @override
  bool get canHandleNewCall => !isCallActive();

  @override
  EncryptionKeyProvider? get keyProvider => null;

  @override
  Future<void> playRingtone() async {}
  @override
  Future<void> stopRingtone() async {}
  @override
  Future<void> registerListeners(CallSession session) async {}
  @override
  Future<void> handleNewCall(CallSession session) async {}
  @override
  Future<void> handleCallEnded(CallSession session) async {}
  @override
  Future<void> handleMissedCall(CallSession session) async {}
  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {}
  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {}
}

/// Applies Deltiecord's explicit desktop-audio choice to MatrixRTC capture.
///
/// matrix-dart-sdk intentionally requests video-only display capture. Wrapping
/// the platform media devices here keeps that SDK detail behind the RTC
/// boundary and still leaves the native portal/browser picker in control of
/// whether a particular window or desktop can actually expose audio.
final class _DeltiecordMediaDevices implements MediaDevices {
  _DeltiecordMediaDevices(this._delegate, this._shareDesktopAudio);

  final MediaDevices _delegate;
  final bool Function() _shareDesktopAudio;

  @override
  Function(dynamic event)? get ondevicechange => _delegate.ondevicechange;

  @override
  set ondevicechange(Function(dynamic event)? callback) {
    _delegate.ondevicechange = callback;
  }

  @override
  Future<MediaStream> getDisplayMedia(Map<String, dynamic> constraints) async {
    final withAudio = _shareDesktopAudio();
    try {
      return await _delegate.getDisplayMedia({
        ...constraints,
        'audio': withAudio,
      });
    } catch (_) {
      if (!withAudio) rethrow;
      // Linux portals and individual windows do not always offer an audio
      // source. Preserve screen sharing in that case instead of failing the
      // entire capture request.
      return _delegate.getDisplayMedia({...constraints, 'audio': false});
    }
  }

  @override
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) =>
      _delegate.getUserMedia(constraints);

  @override
  // Required by MediaDevices for older native backends.
  // ignore: deprecated_member_use
  Future<List<dynamic>> getSources() => _delegate.getSources();

  @override
  Future<List<MediaDeviceInfo>> enumerateDevices() =>
      _delegate.enumerateDevices();

  @override
  MediaTrackSupportedConstraints getSupportedConstraints() =>
      _delegate.getSupportedConstraints();

  @override
  Future<MediaDeviceInfo> selectAudioOutput([AudioOutputOptions? options]) =>
      _delegate.selectAudioOutput(options);
}
