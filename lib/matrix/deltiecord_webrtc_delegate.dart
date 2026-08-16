import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

/// Supplies the Matrix SDK with flutter_webrtc primitives.
///
/// Call presentation remains in the application layer. The delegate deliberately
/// has no UI side effects, which also makes it reusable by the future Android UI.
class DeltiecordWebRtcDelegate implements WebRTCDelegate {
  DeltiecordWebRtcDelegate({required this.isCallActive});

  final bool Function() isCallActive;

  @override
  MediaDevices get mediaDevices => flutter_webrtc.navigator.mediaDevices;

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
