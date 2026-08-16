import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

class VoiceRoomView extends StatefulWidget {
  const VoiceRoomView({required this.backend, required this.room, super.key});

  final ChatBackend backend;
  final RoomSummary room;

  @override
  State<VoiceRoomView> createState() => _VoiceRoomViewState();
}

class _VoiceRoomViewState extends State<VoiceRoomView> {
  String? _pinnedStreamId;
  bool _showOwnPreview = true;
  final Map<String, Future<UserProfileSummary>> _profiles = {};

  @override
  void initState() {
    super.initState();
    unawaited(widget.backend.refreshAudioInputs());
  }

  Future<UserProfileSummary> _profileFor(String userId) => _profiles
      .putIfAbsent(userId, () => widget.backend.getUserProfile(userId));

  Future<void> _showDeviceSettings() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Voice devices'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: _DeviceSelectors(backend: widget.backend),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _showStreamFullscreen(RtcMediaStreamSummary stream) =>
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierColor: Colors.black,
        builder: (context) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: _FullscreenRtcView(stream: stream),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final connectedHere = backend.activeVoiceRoomId == widget.room.id;
    final streams =
        backend.rtcMediaStreams
            .where((stream) => !stream.videoMuted)
            .where(
              (stream) =>
                  _showOwnPreview || !stream.local || stream.screenShare,
            )
            .toList(growable: false)
          ..sort(
            (a, b) => b.screenShare
                ? 1
                : a.screenShare
                ? -1
                : 0,
          );
    if (_pinnedStreamId != null &&
        !streams.any((stream) => stream.id == _pinnedStreamId)) {
      _pinnedStreamId = null;
    }
    return Column(
      children: [
        _VoiceHeader(
          room: widget.room,
          backend: backend,
          showOwnPreview: _showOwnPreview,
          onToggleOwnPreview: () =>
              setState(() => _showOwnPreview = !_showOwnPreview),
          onOpenDevices: _showDeviceSettings,
        ),
        if (backend.voiceScreenSharing)
          Container(
            width: double.infinity,
            color: const Color(0xff4c3d24),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.screen_share, size: 17),
                const SizedBox(width: 8),
                const Expanded(child: Text('You are sharing your screen')),
                TextButton(
                  onPressed: () => backend.setVoiceScreenSharing(false),
                  child: const Text('Stop sharing'),
                ),
              ],
            ),
          ),
        Expanded(
          child:
              connectedHere &&
                  (streams.isNotEmpty || backend.voiceCameraEnabled)
              ? _VideoStage(
                  streams: streams,
                  pinnedStreamId: _pinnedStreamId,
                  participants: widget.room.voiceParticipants,
                  profileFor: _profileFor,
                  onFullscreen: _showStreamFullscreen,
                  onPin: (id) => setState(
                    () => _pinnedStreamId = _pinnedStreamId == id ? null : id,
                  ),
                )
              : _VoiceLobby(
                  backend: backend,
                  room: widget.room,
                  profileFor: _profileFor,
                ),
        ),
      ],
    );
  }
}

class _VoiceHeader extends StatelessWidget {
  const _VoiceHeader({
    required this.room,
    required this.backend,
    required this.showOwnPreview,
    required this.onToggleOwnPreview,
    required this.onOpenDevices,
  });

  final RoomSummary room;
  final ChatBackend backend;
  final bool showOwnPreview;
  final VoidCallback onToggleOwnPreview;
  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: context.deltiecord.surface,
      border: Border(bottom: BorderSide(color: context.deltiecord.divider)),
    ),
    child: Row(
      children: [
        const Icon(Icons.volume_up_outlined, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            room.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (backend.voiceConnectionStatus == VoiceConnectionStatus.connecting)
          const Text('Connecting…')
        else if (backend.voiceConnectionStatus ==
            VoiceConnectionStatus.reconnecting)
          const Text('Reconnecting…')
        else if (backend.voiceConnectionStatus == VoiceConnectionStatus.error)
          const Text('Connection error'),
        const SizedBox(width: 8),
        PopupMenuButton<_VoiceMenuAction>(
          tooltip: 'Voice options',
          icon: const Icon(Icons.more_horiz),
          onSelected: (action) {
            switch (action) {
              case _VoiceMenuAction.devices:
                onOpenDevices();
              case _VoiceMenuAction.mute:
                backend.setVoiceMuted(!backend.voiceMuted);
              case _VoiceMenuAction.deafen:
                backend.setVoiceDeafened(!backend.voiceDeafened);
              case _VoiceMenuAction.camera:
                backend.setVoiceCameraEnabled(!backend.voiceCameraEnabled);
              case _VoiceMenuAction.share:
                backend.setVoiceScreenSharing(!backend.voiceScreenSharing);
              case _VoiceMenuAction.desktopAudio:
                backend.updatePreferences(
                  backend.preferences.copyWith(
                    shareDesktopAudio: !backend.preferences.shareDesktopAudio,
                  ),
                );
              case _VoiceMenuAction.preview:
                onToggleOwnPreview();
              case _VoiceMenuAction.disconnect:
                backend.leaveVoiceRoom();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _VoiceMenuAction.devices,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.tune),
                title: Text('Audio & video devices'),
              ),
            ),
            PopupMenuItem(
              value: _VoiceMenuAction.mute,
              child: ListTile(
                dense: true,
                leading: Icon(backend.voiceMuted ? Icons.mic : Icons.mic_off),
                title: Text(backend.voiceMuted ? 'Unmute' : 'Mute'),
              ),
            ),
            PopupMenuItem(
              value: _VoiceMenuAction.deafen,
              child: ListTile(
                dense: true,
                leading: Icon(
                  backend.voiceDeafened ? Icons.headphones : Icons.headset_off,
                ),
                title: Text(backend.voiceDeafened ? 'Undeafen' : 'Deafen'),
              ),
            ),
            PopupMenuItem(
              value: _VoiceMenuAction.camera,
              child: ListTile(
                dense: true,
                leading: Icon(
                  backend.voiceCameraEnabled
                      ? Icons.videocam_off
                      : Icons.videocam,
                ),
                title: Text(
                  backend.voiceCameraEnabled ? 'Camera off' : 'Camera on',
                ),
              ),
            ),
            PopupMenuItem(
              value: _VoiceMenuAction.share,
              child: ListTile(
                dense: true,
                leading: Icon(
                  backend.voiceScreenSharing
                      ? Icons.stop_screen_share
                      : Icons.screen_share,
                ),
                title: Text(
                  backend.voiceScreenSharing
                      ? 'Stop screen sharing'
                      : 'Share screen',
                ),
              ),
            ),
            CheckedPopupMenuItem(
              value: _VoiceMenuAction.desktopAudio,
              checked: backend.preferences.shareDesktopAudio,
              child: const Text('Share desktop audio'),
            ),
            CheckedPopupMenuItem(
              value: _VoiceMenuAction.preview,
              checked: showOwnPreview,
              child: const Text('Show own preview'),
            ),
            if (backend.activeVoiceRoomId == room.id)
              PopupMenuItem(
                value: _VoiceMenuAction.disconnect,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.call_end,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Disconnect',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

enum _VoiceMenuAction {
  devices,
  mute,
  deafen,
  camera,
  share,
  desktopAudio,
  preview,
  disconnect,
}

class _VoiceLobby extends StatelessWidget {
  const _VoiceLobby({
    required this.backend,
    required this.room,
    required this.profileFor,
  });

  final ChatBackend backend;
  final RoomSummary room;
  final Future<UserProfileSummary> Function(String userId) profileFor;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (room.voiceParticipants.isEmpty)
        const Center(child: Text('Nobody is connected'))
      else
        _ParticipantGrid(
          backend: backend,
          participants: room.voiceParticipants,
          profileFor: profileFor,
        ),
      if (backend.voiceError case final error?)
        Positioned(
          left: 16,
          right: 16,
          top: 12,
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xffff9b9b)),
          ),
        ),
      if (backend.activeVoiceRoomId != room.id)
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Center(
            child: FilledButton.icon(
              onPressed:
                  backend.voiceConnectionStatus ==
                          VoiceConnectionStatus.connecting ||
                      backend.voiceConnectionStatus ==
                          VoiceConnectionStatus.reconnecting
                  ? null
                  : () => backend.joinVoiceRoom(room.id),
              icon: const Icon(Icons.headset),
              label: const Text('Join voice'),
            ),
          ),
        ),
    ],
  );
}

class _ParticipantGrid extends StatelessWidget {
  const _ParticipantGrid({
    required this.backend,
    required this.participants,
    required this.profileFor,
  });

  final ChatBackend backend;
  final List<VoiceParticipantSummary> participants;
  final Future<UserProfileSummary> Function(String userId) profileFor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1100
          ? 4
          : constraints.maxWidth >= 760
          ? 3
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      return GridView.builder(
        padding: const EdgeInsets.all(18),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 16 / 10,
        ),
        itemCount: participants.length,
        itemBuilder: (context, index) => _ParticipantCard(
          backend: backend,
          participant: participants[index],
          profile: profileFor(participants[index].userId),
        ),
      );
    },
  );
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({
    required this.backend,
    required this.participant,
    required this.profile,
  });

  final ChatBackend backend;
  final VoiceParticipantSummary participant;
  final Future<UserProfileSummary> profile;

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfileSummary>(
    future: profile,
    builder: (context, snapshot) {
      final details = snapshot.data;
      final avatar = details?.avatarBytes ?? participant.avatarBytes;
      final top = Color(
        details?.profileColor ??
            Theme.of(context).colorScheme.primary.toARGB32(),
      );
      final bottom = Color(
        details?.profileColorSecondary ?? context.deltiecord.panel.toARGB32(),
      );
      final own = participant.userId == backend.userId;
      return Container(
        decoration: BoxDecoration(
          borderRadius: DeltiecordCorners.borderRadius,
          border: Border.all(
            color: participant.speaking
                ? const Color(0xff76d49b)
                : context.deltiecord.divider,
            width: participant.speaking ? 3 : 1,
          ),
          image: details?.bannerBytes == null
              ? null
              : DecorationImage(
                  image: MemoryImage(details!.bannerBytes!),
                  fit: BoxFit.cover,
                ),
          gradient: details?.bannerBytes == null
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top, bottom],
                )
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x14000000), Color(0x9c000000)],
                ),
              ),
            ),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: EdgeInsets.all(participant.speaking ? 4 : 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: participant.speaking
                      ? const Color(0xff76d49b)
                      : const Color(0x66000000),
                ),
                child: CircleAvatar(
                  radius: 46,
                  backgroundImage: avatar == null ? null : MemoryImage(avatar),
                  child: avatar == null
                      ? Text(
                          participant.displayName.characters.firstOrNull ?? '?',
                          style: const TextStyle(fontSize: 30),
                        )
                      : null,
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${participant.displayName}${own ? ' (you)' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (participant.speaking)
                    const Icon(
                      Icons.graphic_eq,
                      color: Color(0xff76d49b),
                      size: 20,
                    ),
                  if (participant.locallyMuted)
                    const Icon(Icons.volume_off, size: 18),
                ],
              ),
            ),
            if (!own)
              Positioned(
                right: 5,
                top: 5,
                child: PopupMenuButton<_ParticipantAction>(
                  tooltip: 'Participant audio',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    if (action == _ParticipantAction.toggleMute) {
                      backend.setParticipantLocallyMuted(
                        participant.userId,
                        !participant.locallyMuted,
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _ParticipantAction.toggleMute,
                      child: Text(
                        participant.locallyMuted
                            ? 'Unmute locally'
                            : 'Mute locally',
                      ),
                    ),
                    PopupMenuItem(
                      enabled: false,
                      child: SizedBox(
                        width: 210,
                        child: Row(
                          children: [
                            const Icon(Icons.volume_down, size: 18),
                            Expanded(
                              child: Slider(
                                value: participant.localVolume,
                                onChanged: participant.locallyMuted
                                    ? null
                                    : (value) => backend.setParticipantVolume(
                                        participant.userId,
                                        value,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

enum _ParticipantAction { toggleMute }

class _DeviceSelectors extends StatelessWidget {
  const _DeviceSelectors({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (backend.audioInputs.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: backend.selectedAudioInputId ?? '',
          decoration: const InputDecoration(labelText: 'Microphone'),
          items: [
            const DropdownMenuItem(value: '', child: Text('System default')),
            for (final device in backend.audioInputs)
              DropdownMenuItem(value: device.id, child: Text(device.label)),
          ],
          onChanged: (id) =>
              backend.selectAudioInput(id?.isEmpty == true ? null : id),
        ),
      if (backend.audioOutputs.isNotEmpty) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: backend.selectedAudioOutputId ?? '',
          decoration: const InputDecoration(labelText: 'Output'),
          items: [
            const DropdownMenuItem(value: '', child: Text('System default')),
            for (final device in backend.audioOutputs)
              DropdownMenuItem(value: device.id, child: Text(device.label)),
          ],
          onChanged: (id) =>
              backend.selectAudioOutput(id?.isEmpty == true ? null : id),
        ),
      ],
      if (backend.cameras.isNotEmpty) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: backend.selectedCameraId ?? '',
          decoration: const InputDecoration(labelText: 'Camera'),
          items: [
            const DropdownMenuItem(value: '', child: Text('System default')),
            for (final device in backend.cameras)
              DropdownMenuItem(value: device.id, child: Text(device.label)),
          ],
          onChanged: (id) =>
              backend.selectCamera(id?.isEmpty == true ? null : id),
        ),
      ],
      const SizedBox(height: 8),
      Row(
        children: [
          const Icon(Icons.mic_outlined, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Slider(
              value: backend.preferences.microphoneVolume,
              onChanged: (value) => backend.updatePreferences(
                backend.preferences.copyWith(microphoneVolume: value),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(backend.preferences.microphoneVolume * 100).round()}%',
              style: const TextStyle(fontSize: DeltiecordTypeScale.normal),
            ),
          ),
        ],
      ),
      Row(
        children: [
          const Icon(Icons.volume_up_outlined, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Slider(
              value: backend.preferences.outputVolume,
              onChanged: (value) => backend.updatePreferences(
                backend.preferences.copyWith(outputVolume: value),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(backend.preferences.outputVolume * 100).round()}%',
              style: const TextStyle(fontSize: DeltiecordTypeScale.normal),
            ),
          ),
        ],
      ),
    ],
  );
}

class _VideoStage extends StatelessWidget {
  const _VideoStage({
    required this.streams,
    required this.pinnedStreamId,
    required this.participants,
    required this.profileFor,
    required this.onFullscreen,
    required this.onPin,
  });

  final List<RtcMediaStreamSummary> streams;
  final String? pinnedStreamId;
  final List<VoiceParticipantSummary> participants;
  final Future<UserProfileSummary> Function(String userId) profileFor;
  final ValueChanged<RtcMediaStreamSummary> onFullscreen;
  final ValueChanged<String> onPin;

  @override
  Widget build(BuildContext context) {
    final pinned = pinnedStreamId == null
        ? null
        : streams.where((stream) => stream.id == pinnedStreamId).firstOrNull;
    final cameraOffParticipants = participants
        .where(
          (participant) => !streams.any(
            (stream) =>
                !stream.screenShare && stream.userId == participant.userId,
          ),
        )
        .toList(growable: false);
    if (pinned != null) {
      return Column(
        children: [
          Expanded(
            child: _RtcVideoTile(
              stream: pinned,
              speaking: _speaking(pinned.userId),
              pinned: true,
              onPin: () => onPin(pinned.id),
              onFullscreen: () => onFullscreen(pinned),
            ),
          ),
          SizedBox(
            height: 128,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final stream in streams.where((item) => item != pinned))
                  SizedBox(
                    width: 190,
                    child: _RtcVideoTile(
                      stream: stream,
                      speaking: _speaking(stream.userId),
                      pinned: false,
                      onPin: () => onPin(stream.id),
                      onFullscreen: () => onFullscreen(stream),
                    ),
                  ),
                for (final participant in cameraOffParticipants)
                  SizedBox(
                    width: 190,
                    child: _RtcAvatarTile(
                      participant: participant,
                      profile: profileFor(participant.userId),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 16 / 9,
          ),
          itemCount: streams.length + cameraOffParticipants.length,
          itemBuilder: (context, index) {
            if (index >= streams.length) {
              return _RtcAvatarTile(
                participant: cameraOffParticipants[index - streams.length],
                profile: profileFor(
                  cameraOffParticipants[index - streams.length].userId,
                ),
              );
            }
            final stream = streams[index];
            return _RtcVideoTile(
              stream: stream,
              speaking: _speaking(stream.userId),
              pinned: false,
              onPin: () => onPin(stream.id),
              onFullscreen: () => onFullscreen(stream),
            );
          },
        );
      },
    );
  }

  bool _speaking(String userId) => participants.any(
    (participant) => participant.userId == userId && participant.speaking,
  );
}

class _RtcAvatarTile extends StatelessWidget {
  const _RtcAvatarTile({required this.participant, required this.profile});

  final VoiceParticipantSummary participant;
  final Future<UserProfileSummary> profile;

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfileSummary>(
    future: profile,
    builder: (context, snapshot) {
      final details = snapshot.data;
      final avatar = details?.avatarBytes ?? participant.avatarBytes;
      final top = Color(
        details?.profileColor ??
            Theme.of(context).colorScheme.primary.toARGB32(),
      );
      final bottom = Color(
        details?.profileColorSecondary ?? context.deltiecord.input.toARGB32(),
      );
      return Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: DeltiecordCorners.borderRadius,
          border: Border.all(
            color: participant.speaking
                ? const Color(0xff76d49b)
                : context.deltiecord.divider,
            width: participant.speaking ? 3 : 1,
          ),
          image: details?.bannerBytes == null
              ? null
              : DecorationImage(
                  image: MemoryImage(details!.bannerBytes!),
                  fit: BoxFit.cover,
                ),
          gradient: details?.bannerBytes == null
              ? LinearGradient(colors: [top, bottom])
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x10000000), Color(0xa0000000)],
                ),
              ),
            ),
            Center(
              child: CircleAvatar(
                radius: 42,
                backgroundImage: avatar == null ? null : MemoryImage(avatar),
                child: avatar == null
                    ? Text(
                        participant.displayName.characters.firstOrNull ?? '?',
                        style: const TextStyle(fontSize: 28),
                      )
                    : null,
              ),
            ),
            Positioned(
              left: 8,
              bottom: 7,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xaa111216)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Text(
                    '${participant.displayName} · camera off',
                    style: const TextStyle(
                      fontSize: DeltiecordTypeScale.normal,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _RtcVideoTile extends StatefulWidget {
  const _RtcVideoTile({
    required this.stream,
    required this.speaking,
    required this.pinned,
    required this.onPin,
    required this.onFullscreen,
  });

  final RtcMediaStreamSummary stream;
  final bool speaking;
  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback onFullscreen;

  @override
  State<_RtcVideoTile> createState() => _RtcVideoTileState();
}

class _RtcVideoTileState extends State<_RtcVideoTile> {
  final _renderer = webrtc.RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  Future<void> _attach() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream.stream;
    if (mounted) setState(() => _ready = true);
  }

  @override
  void didUpdateWidget(covariant _RtcVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream.stream != widget.stream.stream) {
      _renderer.srcObject = widget.stream.stream;
    }
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onPin,
    onDoubleTap: widget.onFullscreen,
    child: Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(
          color: widget.speaking
              ? const Color(0xff76d49b)
              : context.deltiecord.divider,
          width: widget.speaking ? 2 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            webrtc.RTCVideoView(
              _renderer,
              mirror: widget.stream.local && !widget.stream.screenShare,
              objectFit: widget.stream.screenShare
                  ? webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                  : webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          Positioned(
            left: 8,
            bottom: 7,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xaa111216)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  '${widget.stream.displayName}${widget.stream.screenShare ? ' · screen' : ''}',
                  style: const TextStyle(fontSize: DeltiecordTypeScale.normal),
                ),
              ),
            ),
          ),
          if (widget.pinned)
            const Positioned(
              right: 8,
              top: 8,
              child: Icon(Icons.push_pin, size: 18),
            ),
          Positioned(
            right: 8,
            bottom: 7,
            child: IconButton.filledTonal(
              tooltip: widget.stream.screenShare
                  ? 'View screen fullscreen'
                  : 'View fullscreen',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onFullscreen,
              icon: const Icon(Icons.fullscreen, size: 20),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FullscreenRtcView extends StatefulWidget {
  const _FullscreenRtcView({required this.stream});

  final RtcMediaStreamSummary stream;

  @override
  State<_FullscreenRtcView> createState() => _FullscreenRtcViewState();
}

class _FullscreenRtcViewState extends State<_FullscreenRtcView> {
  final _renderer = webrtc.RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  Future<void> _attach() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream.stream;
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
    },
    child: Focus(
      autofocus: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            webrtc.RTCVideoView(
              _renderer,
              mirror: widget.stream.local && !widget.stream.screenShare,
              objectFit:
                  webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            )
          else
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          Positioned(
            left: 18,
            top: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xaa111216),
                borderRadius: DeltiecordCorners.borderRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '${widget.stream.displayName}${widget.stream.screenShare ? ' · screen share' : ''}',
                ),
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: IconButton.filled(
              tooltip: 'Exit fullscreen',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );
}
