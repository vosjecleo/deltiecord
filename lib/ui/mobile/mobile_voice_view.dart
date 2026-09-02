import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/avatar_color.dart';
import 'mobile_widgets.dart';

Color _voiceAvatarBorder(BuildContext context) {
  final background = Theme.of(context).scaffoldBackgroundColor;
  if (background.computeLuminance() < 0.01) return Colors.white;
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xffb8bac2)
      : Colors.black;
}

class MobileVoiceView extends StatefulWidget {
  const MobileVoiceView({
    required this.backend,
    required this.room,
    required this.onOpenNavigation,
    required this.onOpenDetails,
    super.key,
  });
  final ChatBackend backend;
  final RoomSummary room;
  final VoidCallback onOpenNavigation;
  final VoidCallback onOpenDetails;

  @override
  State<MobileVoiceView> createState() => _MobileVoiceViewState();
}

class _MobileVoiceViewState extends State<MobileVoiceView> {
  final Map<String, Future<UserProfileSummary>> _profiles = {};

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final connected = backend.activeVoiceRoomId == widget.room.id;
    final streams = backend.rtcMediaStreams
        .where((item) => !item.videoMuted)
        .toList();
    final users = <String>{
      ...widget.room.voiceParticipants.map((item) => item.userId),
      ...streams.map((item) => item.userId),
      if (connected && backend.userId != null) backend.userId!,
    }.toList();
    return Scaffold(
      key: const ValueKey('mobile-voice-view'),
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onOpenNavigation,
          icon: const Icon(Icons.menu),
        ),
        title: InkWell(
          onTap: widget.onOpenDetails,
          child: Row(
            children: [
              const Icon(Icons.volume_up_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.room.name)),
            ],
          ),
        ),
        actions: [
          Tooltip(
            message: switch (backend.voiceConnectionStatus) {
              VoiceConnectionStatus.connected => 'Network quality: connected',
              VoiceConnectionStatus.reconnecting =>
                'Network quality: reconnecting',
              VoiceConnectionStatus.error => 'Network quality: poor',
              _ => 'Call is not connected',
            },
            child: Icon(
              backend.voiceConnectionStatus == VoiceConnectionStatus.connected
                  ? Icons.signal_cellular_alt
                  : backend.voiceConnectionStatus ==
                        VoiceConnectionStatus.reconnecting
                  ? Icons.signal_cellular_alt_2_bar
                  : Icons.signal_cellular_alt_1_bar,
              color:
                  backend.voiceConnectionStatus == VoiceConnectionStatus.error
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) {
              switch (action) {
                case 'mute':
                  backend.setVoiceMuted(!backend.voiceMuted);
                case 'deafen':
                  backend.setVoiceDeafened(!backend.voiceDeafened);
                case 'camera':
                  backend.setVoiceCameraEnabled(!backend.voiceCameraEnabled);
                case 'share':
                  backend.setVoiceScreenSharing(!backend.voiceScreenSharing);
                case 'devices':
                  _showDeviceSheet();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mute',
                child: Text(backend.voiceMuted ? 'Unmute' : 'Mute'),
              ),
              PopupMenuItem(
                value: 'deafen',
                child: Text(backend.voiceDeafened ? 'Undeafen' : 'Deafen'),
              ),
              PopupMenuItem(
                value: 'camera',
                child: Text(
                  backend.voiceCameraEnabled ? 'Camera off' : 'Camera on',
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Text(
                  backend.voiceScreenSharing ? 'Stop sharing' : 'Share screen',
                ),
              ),
              const PopupMenuItem(
                value: 'devices',
                child: Text('Audio and camera devices'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (backend.voiceConnectionStatus ==
              VoiceConnectionStatus.reconnecting)
            const LinearProgressIndicator(),
          Expanded(
            child: users.isEmpty
                ? const Center(child: Text('Nobody connected'))
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 360,
                          childAspectRatio: 1.15,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final userId = users[index];
                      final stream = streams
                          .where((item) => item.userId == userId)
                          .firstOrNull;
                      final participant = widget.room.voiceParticipants
                          .where((item) => item.userId == userId)
                          .firstOrNull;
                      return _VoiceParticipantTile(
                        backend: backend,
                        userId: userId,
                        stream: stream,
                        participant: participant,
                        speaking: participant?.speaking ?? false,
                        selfSpeaking:
                            userId == backend.userId &&
                            !backend.voiceMuted &&
                            backend.voiceInputLevel > 0.035,
                        profile: _profiles.putIfAbsent(
                          userId,
                          () => backend.getUserProfile(userId),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: connected
                  ? FilledButton.icon(
                      onPressed: backend.leaveVoiceRoom,
                      icon: const Icon(Icons.call_end),
                      label: const Text('Disconnect'),
                    )
                  : FilledButton.icon(
                      onPressed: () => backend.joinVoiceRoom(widget.room.id),
                      icon: const Icon(Icons.headset),
                      label: const Text('Join voice'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeviceSheet() async {
    await widget.backend.refreshAudioInputs();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text('Microphone', style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<String>(
              groupValue: widget.backend.selectedAudioInputId,
              onChanged: (value) {
                widget.backend.selectAudioInput(value);
                Navigator.pop(context);
              },
              child: Column(
                children: [
                  for (final input in widget.backend.audioInputs)
                    RadioListTile<String>(
                      value: input.id,
                      title: Text(input.label),
                    ),
                ],
              ),
            ),
            const Divider(),
            Text('Speaker', style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<String>(
              groupValue: widget.backend.selectedAudioOutputId,
              onChanged: (value) {
                widget.backend.selectAudioOutput(value);
                Navigator.pop(context);
              },
              child: Column(
                children: [
                  for (final output in widget.backend.audioOutputs)
                    RadioListTile<String>(
                      value: output.id,
                      title: Text(output.label),
                    ),
                ],
              ),
            ),
            const Divider(),
            Text('Camera', style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<String>(
              groupValue: widget.backend.selectedCameraId,
              onChanged: (value) {
                widget.backend.selectCamera(value);
                Navigator.pop(context);
              },
              child: Column(
                children: [
                  for (final camera in widget.backend.cameras)
                    RadioListTile<String>(
                      value: camera.id,
                      title: Text(camera.label),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Noise suppression'),
              value: widget.backend.preferences.noiseSuppression,
              onChanged: (value) => widget.backend.updatePreferences(
                widget.backend.preferences.copyWith(noiseSuppression: value),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Echo cancellation'),
              value: widget.backend.preferences.echoCancellation,
              onChanged: (value) => widget.backend.updatePreferences(
                widget.backend.preferences.copyWith(echoCancellation: value),
              ),
            ),
            if (widget.backend.audioInputs.isEmpty &&
                widget.backend.cameras.isEmpty)
              const ListTile(
                title: Text('Use Android system devices'),
                subtitle: Text(
                  'This device does not expose manual capture selection.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VoiceParticipantTile extends StatelessWidget {
  const _VoiceParticipantTile({
    required this.backend,
    required this.userId,
    required this.stream,
    required this.speaking,
    required this.selfSpeaking,
    required this.profile,
    required this.participant,
  });
  final ChatBackend backend;
  final String userId;
  final RtcMediaStreamSummary? stream;
  final bool speaking;
  final bool selfSpeaking;
  final Future<UserProfileSummary> profile;
  final VoiceParticipantSummary? participant;

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfileSummary>(
    future: profile,
    builder: (context, snapshot) {
      final profile = snapshot.data;
      final media = stream;
      final isSpeaking = speaking || selfSpeaking;
      return FutureBuilder<Color>(
        future: profile?.voiceColor != null
            ? Future.value(Color(profile!.voiceColor!))
            : representativeAvatarColor(profile?.avatarBytes),
        builder: (context, colorSnapshot) => GestureDetector(
          onDoubleTap: media == null ? null : () => _fullscreen(context, media),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSpeaking
                    ? const Color(0xff23c483)
                    : Theme.of(context).dividerColor,
                width: isSpeaking ? 3 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (media != null)
                  _RtcVideo(stream: media)
                else if (profile?.voiceBackgroundBytes case final banner?)
                  Image.memory(banner, fit: BoxFit.cover)
                else
                  ColoredBox(
                    color: colorSnapshot.data ?? const Color(0xff353846),
                  ),
                if (media == null)
                  Center(
                    child: MobileAvatar(
                      bytes: profile?.avatarBytes,
                      fallback: profile?.displayName ?? userId,
                      size: 86,
                      borderColor: _voiceAvatarBorder(context),
                      speaking: isSpeaking,
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile?.displayName ?? userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(blurRadius: 5, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                      if (isSpeaking)
                        const Icon(Icons.graphic_eq, color: Color(0xff23c483)),
                    ],
                  ),
                ),
                if (userId != backend.userId)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton.filledTonal(
                      tooltip: 'Local participant controls',
                      onPressed: () => _participantControls(context),
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Future<void> _participantControls(BuildContext context) async {
    var volume = participant?.localVolume ?? 1;
    var muted = participant?.locallyMuted ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(participant?.displayName ?? userId),
                  trailing: IconButton(
                    tooltip: muted ? 'Unmute locally' : 'Mute locally',
                    onPressed: () {
                      muted = !muted;
                      setSheetState(() {});
                      backend.setParticipantLocallyMuted(userId, muted);
                    },
                    icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.volume_down),
                    Expanded(
                      child: Slider(
                        value: volume,
                        onChanged: (value) {
                          volume = value;
                          setSheetState(() {});
                          backend.setParticipantVolume(userId, value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${(volume * 100).round()}%'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _fullscreen(
    BuildContext context,
    RtcMediaStreamSummary stream,
  ) => showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: _RtcVideo(stream: stream)),
          Positioned(
            right: 12,
            top: 12,
            child: SafeArea(
              child: IconButton.filled(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RtcVideo extends StatefulWidget {
  const _RtcVideo({required this.stream});
  final RtcMediaStreamSummary stream;

  @override
  State<_RtcVideo> createState() => _RtcVideoState();
}

class _RtcVideoState extends State<_RtcVideo> {
  final _renderer = webrtc.RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream.stream;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _RtcVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream.id != widget.stream.id) {
      _renderer.srcObject = widget.stream.stream;
    }
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    unawaited(_renderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => webrtc.RTCVideoView(
    _renderer,
    mirror: widget.stream.local && !widget.stream.screenShare,
    objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
  );
}

class MobileCallIsland extends StatelessWidget {
  const MobileCallIsland({
    required this.backend,
    required this.onOpen,
    super.key,
  });
  final ChatBackend backend;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('mobile-call-island'),
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headset, size: 19),
            const SizedBox(width: 8),
            Text(
              backend.voiceConnectionStatus ==
                      VoiceConnectionStatus.reconnecting
                  ? 'Reconnecting…'
                  : 'Voice connected',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => backend.setVoiceMuted(!backend.voiceMuted),
              icon: Icon(backend.voiceMuted ? Icons.mic_off : Icons.mic),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              color: Colors.redAccent,
              onPressed: backend.leaveVoiceRoom,
              icon: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    ),
  );
}
