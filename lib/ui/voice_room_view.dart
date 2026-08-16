import 'dart:async';

import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(widget.backend.refreshAudioInputs());
  }

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
        _VoiceHeader(room: widget.room, backend: backend),
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
              ? Row(
                  children: [
                    Expanded(
                      child: _VideoStage(
                        streams: streams,
                        pinnedStreamId: _pinnedStreamId,
                        participants: widget.room.voiceParticipants,
                        onPin: (id) => setState(
                          () => _pinnedStreamId = _pinnedStreamId == id
                              ? null
                              : id,
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 280,
                      child: _ParticipantPanel(
                        backend: backend,
                        room: widget.room,
                      ),
                    ),
                  ],
                )
              : _VoiceLobby(backend: backend, room: widget.room),
        ),
        if (connectedHere)
          _VoiceBottomBar(
            backend: backend,
            showOwnPreview: _showOwnPreview,
            onToggleOwnPreview: () =>
                setState(() => _showOwnPreview = !_showOwnPreview),
          ),
      ],
    );
  }
}

class _VoiceHeader extends StatelessWidget {
  const _VoiceHeader({required this.room, required this.backend});

  final RoomSummary room;
  final ChatBackend backend;

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
      ],
    ),
  );
}

class _VoiceLobby extends StatelessWidget {
  const _VoiceLobby({required this.backend, required this.room});

  final ChatBackend backend;
  final RoomSummary room;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.headset_mic_outlined, size: 42),
          const SizedBox(height: 12),
          Text(
            room.voiceParticipants.isEmpty
                ? 'Nobody is connected'
                : '${room.voiceParticipants.length} connected',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: DeltiecordTypeScale.bigUi,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (final participant in room.voiceParticipants)
            _ParticipantTile(backend: backend, participant: participant),
          if (backend.voiceError case final error?) ...[
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xffff9b9b)),
            ),
          ],
          const SizedBox(height: 18),
          _DeviceSelectors(backend: backend),
          const SizedBox(height: 12),
          if (backend.activeVoiceRoomId != room.id)
            FilledButton.icon(
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
        ],
      ),
    ),
  );
}

class _ParticipantPanel extends StatelessWidget {
  const _ParticipantPanel({required this.backend, required this.room});

  final ChatBackend backend;
  final RoomSummary room;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
    children: [
      Text(
        '${room.voiceParticipants.length} connected',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 6),
      for (final participant in room.voiceParticipants)
        _ParticipantTile(backend: backend, participant: participant),
      const Divider(height: 22),
      const Text(
        'Input level',
        style: TextStyle(fontSize: DeltiecordTypeScale.normal),
      ),
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: backend.voiceMuted ? 0 : backend.voiceInputLevel,
        minHeight: 5,
      ),
      const SizedBox(height: 14),
      _DeviceSelectors(backend: backend),
    ],
  );
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.backend, required this.participant});

  final ChatBackend backend;
  final VoiceParticipantSummary participant;

  @override
  Widget build(BuildContext context) {
    final own = participant.userId == backend.userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        border: participant.speaking
            ? Border.all(color: const Color(0xff76d49b))
            : null,
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundImage: participant.avatarBytes == null
                  ? null
                  : MemoryImage(participant.avatarBytes!),
              child: participant.avatarBytes == null
                  ? Text(participant.displayName.characters.firstOrNull ?? '?')
                  : null,
            ),
            title: Text(participant.displayName),
            trailing: participant.speaking
                ? const Icon(Icons.graphic_eq, color: Color(0xff76d49b))
                : participant.locallyMuted
                ? const Icon(Icons.volume_off, size: 17)
                : null,
            onLongPress: own
                ? null
                : () => backend.setParticipantLocallyMuted(
                    participant.userId,
                    !participant.locallyMuted,
                  ),
          ),
          if (!own)
            Row(
              children: [
                IconButton(
                  tooltip: participant.locallyMuted
                      ? 'Unmute locally'
                      : 'Mute locally',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => backend.setParticipantLocallyMuted(
                    participant.userId,
                    !participant.locallyMuted,
                  ),
                  icon: Icon(
                    participant.locallyMuted
                        ? Icons.volume_off
                        : Icons.volume_down,
                    size: 16,
                  ),
                ),
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
        ],
      ),
    );
  }
}

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

class _VoiceBottomBar extends StatelessWidget {
  const _VoiceBottomBar({
    required this.backend,
    required this.showOwnPreview,
    required this.onToggleOwnPreview,
  });

  final ChatBackend backend;
  final bool showOwnPreview;
  final VoidCallback onToggleOwnPreview;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: context.deltiecord.panel),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 7,
      runSpacing: 7,
      children: [
        OutlinedButton.icon(
          onPressed: () => backend.setVoiceMuted(!backend.voiceMuted),
          icon: Icon(backend.voiceMuted ? Icons.mic_off : Icons.mic),
          label: Text(backend.voiceMuted ? 'Unmute' : 'Mute'),
          style: OutlinedButton.styleFrom(
            foregroundColor: backend.voiceMuted
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => backend.setVoiceDeafened(!backend.voiceDeafened),
          icon: Icon(
            backend.voiceDeafened ? Icons.headset_off : Icons.headphones,
          ),
          label: Text(backend.voiceDeafened ? 'Undeafen' : 'Deafen'),
          style: OutlinedButton.styleFrom(
            foregroundColor: backend.voiceDeafened
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              backend.setVoiceCameraEnabled(!backend.voiceCameraEnabled),
          icon: Icon(
            backend.voiceCameraEnabled ? Icons.videocam : Icons.videocam_off,
          ),
          label: Text(backend.voiceCameraEnabled ? 'Camera off' : 'Camera on'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              backend.setVoiceScreenSharing(!backend.voiceScreenSharing),
          icon: Icon(
            backend.voiceScreenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share,
          ),
          label: Text(backend.voiceScreenSharing ? 'Stop share' : 'Share'),
        ),
        IconButton(
          tooltip: showOwnPreview ? 'Hide own preview' : 'Show own preview',
          onPressed: onToggleOwnPreview,
          icon: Icon(showOwnPreview ? Icons.visibility : Icons.visibility_off),
        ),
        FilledButton.icon(
          onPressed: backend.leaveVoiceRoom,
          icon: const Icon(Icons.call_end),
          label: const Text('Disconnect'),
        ),
      ],
    ),
  );
}

class _VideoStage extends StatelessWidget {
  const _VideoStage({
    required this.streams,
    required this.pinnedStreamId,
    required this.participants,
    required this.onPin,
  });

  final List<RtcMediaStreamSummary> streams;
  final String? pinnedStreamId;
  final List<VoiceParticipantSummary> participants;
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
                    ),
                  ),
                for (final participant in cameraOffParticipants)
                  SizedBox(
                    width: 190,
                    child: _RtcAvatarTile(participant: participant),
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
              );
            }
            final stream = streams[index];
            return _RtcVideoTile(
              stream: stream,
              speaking: _speaking(stream.userId),
              pinned: false,
              onPin: () => onPin(stream.id),
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
  const _RtcAvatarTile({required this.participant});

  final VoiceParticipantSummary participant;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.deltiecord.input,
      border: Border.all(
        color: participant.speaking
            ? const Color(0xff76d49b)
            : context.deltiecord.divider,
        width: participant.speaking ? 2 : 1,
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundImage: participant.avatarBytes == null
                ? null
                : MemoryImage(participant.avatarBytes!),
            child: participant.avatarBytes == null
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                '${participant.displayName} · camera off',
                style: const TextStyle(fontSize: DeltiecordTypeScale.normal),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _RtcVideoTile extends StatefulWidget {
  const _RtcVideoTile({
    required this.stream,
    required this.speaking,
    required this.pinned,
    required this.onPin,
  });

  final RtcMediaStreamSummary stream;
  final bool speaking;
  final bool pinned;
  final VoidCallback onPin;

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
        ],
      ),
    ),
  );
}
