part of 'chat_shell.dart';

String _formatMessageClock(DateTime value, {required bool use24HourTime}) {
  final minutes = value.minute.toString().padLeft(2, '0');
  if (use24HourTime) {
    return '${value.hour.toString().padLeft(2, '0')}:$minutes';
  }
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour:$minutes ${value.hour < 12 ? 'AM' : 'PM'}';
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.highlighted,
    required this.startsGroup,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onRetry,
    required this.onCancel,
    required this.onToggleReaction,
    required this.onJumpToReply,
    required this.mediaMessages,
    required this.backend,
    required this.onShowProfile,
    required this.onActionsShown,
  });

  final ChatMessage message;
  final bool highlighted;
  final bool startsGroup;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final ValueChanged<ReactionSummary> onToggleReaction;
  final ValueChanged<String> onJumpToReply;
  final List<ChatMessage> mediaMessages;
  final ChatBackend backend;
  final ValueChanged<(RoomMemberSummary, Offset?)> onShowProfile;
  final ValueChanged<VoidCallback> onActionsShown;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  Timer? _dismissActionsTimer;
  final _actionsOverlay = OverlayPortalController();
  bool _hovered = false;
  bool _actionsHovered = false;
  Offset _actionsPosition = Offset.zero;
  Offset? _profileAnchorPosition;

  ChatMessage get message => widget.message;

  void _showSenderProfile() {
    final userId = message.senderId;
    if (userId == null) return;
    final members = widget.backend.selectedRoomMembers;
    final member = members
        .where((candidate) => candidate.userId == userId)
        .firstOrNull;
    widget.onShowProfile((
      member ??
          RoomMemberSummary(
            userId: userId,
            displayName: message.sender,
            avatarBytes: message.avatarBytes,
            presence: UserPresence.offline,
          ),
      _profileAnchorPosition,
    ));
  }

  void _enter(PointerEnterEvent _) {
    setState(() => _hovered = true);
  }

  void _exit(PointerExitEvent _) {
    setState(() => _hovered = false);
  }

  void _showActions(Offset globalPosition) {
    _dismissActionsTimer?.cancel();
    final viewport = MediaQuery.sizeOf(context);
    setState(() {
      _actionsHovered = false;
      _actionsPosition = Offset(
        globalPosition.dx.clamp(0, max(0, viewport.width - 224)),
        globalPosition.dy.clamp(0, viewport.height - 48),
      );
    });
    widget.onActionsShown(_hideActions);
    _actionsOverlay.show();
    _scheduleActionsDismissal();
  }

  void _hideActions() {
    _dismissActionsTimer?.cancel();
    _actionsHovered = false;
    _actionsOverlay.hide();
  }

  void _actionsEnter(PointerEnterEvent _) {
    _dismissActionsTimer?.cancel();
    _actionsHovered = true;
  }

  void _actionsExit(PointerExitEvent _) {
    _actionsHovered = false;
    _scheduleActionsDismissal();
  }

  void _scheduleActionsDismissal() {
    _dismissActionsTimer?.cancel();
    _dismissActionsTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_actionsHovered) {
        _actionsOverlay.hide();
      }
    });
  }

  void _performAction(VoidCallback? action) {
    action?.call();
    _hideActions();
  }

  @override
  void dispose() {
    _dismissActionsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compactness = widget.backend.preferences.compactness;
    final groupTop = 11 - (compactness * 5);
    final continuationTop = 4 - (compactness * 3);
    final rowBottom = 3 - (compactness * 2);
    final local = message.timestamp.toLocal();
    final now = DateTime.now();
    final clock = _formatMessageClock(
      local,
      use24HourTime: widget.backend.preferences.use24HourTime,
    );
    final time =
        local.year == now.year &&
            local.month == now.month &&
            local.day == now.day
        ? clock
        : '${local.day}/${local.month}/${local.year} $clock';
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
        child: Text(
          message.body,
          style: const TextStyle(
            color: Color(0xff989aa5),
            fontSize: DeltiecordTypeScale.normal,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return OverlayPortal(
      controller: _actionsOverlay,
      overlayChildBuilder: (context) => Positioned(
        left: _actionsPosition.dx,
        top: _actionsPosition.dy,
        child: MouseRegion(
          onEnter: _actionsEnter,
          onExit: _actionsExit,
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.deltiecord.elevated,
                borderRadius: DeltiecordCorners.borderRadius,
              ),
              child: _MessageActions(
                onReply: () => _performAction(widget.onReply),
                onCopy: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: message.body)),
                  );
                  _hideActions();
                },
                onBookmark: () => _performAction(
                  () => widget.backend.toggleMessageBookmarked(message.id),
                ),
                bookmarked: message.bookmarked,
                onPin: message.canRedact
                    ? () => _performAction(
                        () => widget.backend.toggleMessagePinned(message.id),
                      )
                    : null,
                pinned: message.pinned,
                onEdit: widget.onEdit == null
                    ? null
                    : () => _performAction(widget.onEdit),
                onDelete: widget.onDelete == null
                    ? null
                    : () => _performAction(widget.onDelete),
                onReact: widget.onReact == null
                    ? null
                    : () => _performAction(widget.onReact),
                onRetry: widget.onRetry == null
                    ? null
                    : () => _performAction(widget.onRetry),
                onCancel: widget.onCancel == null
                    ? null
                    : () => _performAction(widget.onCancel),
              ),
            ),
          ),
        ),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            _showActions(event.position);
          }
        },
        child: MouseRegion(
          onEnter: _enter,
          onExit: _exit,
          child: AnimatedContainer(
            key: Key('message-row-${message.id}'),
            duration: widget.backend.preferences.reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 110),
            decoration: BoxDecoration(
              color: message.pingedCurrentUser
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.11)
                  : _hovered || widget.highlighted
                  ? context.deltiecord.hover
                  : Colors.transparent,
              border: message.pingedCurrentUser
                  ? Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    )
                  : null,
            ),
            child: Opacity(
              opacity: message.pending ? 0.55 : 1,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      widget.startsGroup ? groupTop : continuationTop,
                      20,
                      rowBottom,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            key: ValueKey('message-content-${message.id}'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (message.reply case final reply?)
                                Transform.translate(
                                  offset: const Offset(-50, 0),
                                  child: InkWell(
                                    key: Key('reply-preview-${message.id}'),
                                    onTap: () =>
                                        widget.onJumpToReply(reply.eventId),
                                    child: Row(
                                      children: [
                                        CustomPaint(
                                          size: const Size(42, 20),
                                          painter: _ReplyConnectorPainter(
                                            color: context.deltiecord.muted,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '${reply.sender}  ',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: reply.body.replaceAll(
                                                    '\n',
                                                    ' ',
                                                  ),
                                                  style: TextStyle(
                                                    color: context
                                                        .deltiecord
                                                        .muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize:
                                                  DeltiecordTypeScale.normal,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (widget.startsGroup)
                                Row(
                                  children: [
                                    Flexible(
                                      child: InkWell(
                                        onTap: _showSenderProfile,
                                        onTapDown: (details) =>
                                            _profileAnchorPosition =
                                                details.globalPosition,
                                        child: Text(
                                          message.sender,
                                          key: ValueKey(
                                            'message-sender-${message.id}',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize:
                                                DeltiecordTypeScale.bigChat,
                                            fontWeight: FontWeight.w600,
                                            height: 1.05,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      time,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontSize: DeltiecordTypeScale.small,
                                            color: context.deltiecord.muted,
                                          ),
                                    ),
                                    if (message.own &&
                                        !message.failed &&
                                        !message.pending) ...[
                                      const SizedBox(width: 5),
                                      Tooltip(
                                        message: message.readBy.isEmpty
                                            ? 'Sent to homeserver'
                                            : 'Read by ${message.readBy.map((reader) => reader.displayName).join(', ')}',
                                        child: Icon(
                                          message.readBy.isEmpty
                                              ? Icons.check
                                              : Icons.done_all,
                                          size: 11,
                                          color: context.deltiecord.muted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              if (message.body.isNotEmpty &&
                                  message.poll == null)
                                KeyedSubtree(
                                  key: ValueKey('message-body-${message.id}'),
                                  child: message.formattedBody != null
                                      ? MatrixHtmlText(
                                          html: message.formattedBody!,
                                          fallback: message.body,
                                          backend: widget.backend,
                                        )
                                      : MatrixPlainText(
                                          text: message.body,
                                          style: TextStyle(
                                            height: 1.16,
                                            fontStyle: message.redacted
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                            color: message.redacted
                                                ? context.deltiecord.muted
                                                : null,
                                          ),
                                        ),
                                ),
                              if (message.poll != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: PollCard(
                                    backend: widget.backend,
                                    message: message,
                                  ),
                                ),
                              if (message.attachment case final attachment?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _AttachmentView(
                                    backend: widget.backend,
                                    messageId: message.id,
                                    attachment: attachment,
                                    gallery: widget.mediaMessages,
                                  ),
                                ),
                              for (final preview in message.linkPreviews)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _LinkPreviewCard(preview: preview),
                                ),
                              if (message.edited)
                                Text(
                                  '(edited)',
                                  style: TextStyle(
                                    fontSize: DeltiecordTypeScale.normal,
                                    color: context.deltiecord.muted,
                                  ),
                                ),
                              if (message.queued)
                                const Text(
                                  'Queued — retrying after reconnect',
                                  style: TextStyle(
                                    fontSize: DeltiecordTypeScale.normal,
                                    color: Color(0xffffc857),
                                  ),
                                )
                              else if (message.failed)
                                Row(
                                  children: [
                                    const Text(
                                      'Failed to send',
                                      style: TextStyle(
                                        fontSize: DeltiecordTypeScale.normal,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: widget.onRetry,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              if (message.transferStatus case final status?)
                                Text(
                                  status,
                                  style: const TextStyle(
                                    fontSize: DeltiecordTypeScale.normal,
                                    color: Color(0xffb8bfff),
                                  ),
                                ),
                              if (message.reactions.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (final reaction in message.reactions)
                                        ActionChip(
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: reaction.reactedByMe
                                              ? const Color(0xff424a78)
                                              : const Color(0xff303139),
                                          // Keep ordinary reactions as one Text
                                          // node for accessibility and the
                                          // established widget contract. Custom
                                          // emoji need a composed image/count row.
                                          label: reaction.customEmoji == null
                                              ? Text(
                                                  '${reaction.key} ${reaction.count}',
                                                  style: TextStyle(
                                                    fontFamily: context
                                                        .deltiecordEmojiFont,
                                                  ),
                                                )
                                              : Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    CustomEmojiImage(
                                                      backend: widget.backend,
                                                      emoji:
                                                          reaction.customEmoji!,
                                                      size: 18,
                                                    ),
                                                    Text(' ${reaction.count}'),
                                                  ],
                                                ),
                                          onPressed: () =>
                                              widget.onToggleReaction(reaction),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.startsGroup)
                    Positioned(
                      // Keep the avatar centred against the sender header and
                      // first content line. The near-equal outer and inner
                      // gutters make the timeline read as one aligned column.
                      left: 11,
                      top: groupTop - 2 + (message.reply == null ? 0 : 22),
                      child: GestureDetector(
                        key: ValueKey('message-avatar-${message.id}'),
                        onTap: _showSenderProfile,
                        onTapDown: (details) =>
                            _profileAnchorPosition = details.globalPosition,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: context.deltiecord.elevated,
                          backgroundImage: message.avatarBytes == null
                              ? null
                              : MemoryImage(message.avatarBytes!),
                          child: message.avatarBytes == null
                              ? Text(
                                  message.sender.trim().isEmpty
                                      ? '?'
                                      : message.sender.characters.first
                                            .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: DeltiecordTypeScale.normal,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyConnectorPainter extends CustomPainter {
  const _ReplyConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.48, size.height)
      ..lineTo(size.width * 0.48, size.height * 0.52)
      ..quadraticBezierTo(
        size.width * 0.48,
        size.height * 0.28,
        size.width * 0.70,
        size.height * 0.28,
      )
      ..lineTo(size.width, size.height * 0.28);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ReplyConnectorPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Divider(color: Color(0xffff6f77), thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 9),
          child: Text(
            'NEW',
            style: TextStyle(
              color: Color(0xffff8b91),
              fontSize: DeltiecordTypeScale.normal,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xffff6f77), thickness: 1)),
      ],
    ),
  );
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.onReply,
    required this.onCopy,
    required this.onBookmark,
    required this.bookmarked,
    required this.onPin,
    required this.pinned,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onRetry,
    required this.onCancel,
  });

  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback onBookmark;
  final bool bookmarked;
  final VoidCallback? onPin;
  final bool pinned;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: const Key('message-action-reply'),
        visualDensity: VisualDensity.compact,
        tooltip: 'Reply',
        onPressed: onReply,
        icon: const Icon(Icons.reply, size: 16),
      ),
      IconButton(
        key: const Key('message-action-bookmark'),
        visualDensity: VisualDensity.compact,
        tooltip: bookmarked ? 'Remove bookmark' : 'Save message',
        onPressed: onBookmark,
        icon: Icon(
          bookmarked ? Icons.bookmark : Icons.bookmark_border,
          size: 16,
        ),
      ),
      if (onPin != null)
        IconButton(
          key: const Key('message-action-pin'),
          visualDensity: VisualDensity.compact,
          tooltip: pinned ? 'Unpin' : 'Pin message',
          onPressed: onPin,
          icon: Icon(
            pinned ? Icons.push_pin : Icons.push_pin_outlined,
            size: 16,
          ),
        ),
      IconButton(
        key: const Key('message-action-copy'),
        visualDensity: VisualDensity.compact,
        tooltip: 'Copy text',
        onPressed: onCopy,
        icon: const Icon(Icons.copy_outlined, size: 16),
      ),
      if (onReact != null)
        IconButton(
          key: const Key('message-action-react'),
          visualDensity: VisualDensity.compact,
          tooltip: 'React',
          onPressed: onReact,
          icon: const Icon(Icons.add_reaction_outlined, size: 16),
        ),
      if (onEdit != null)
        IconButton(
          key: const Key('message-action-edit'),
          visualDensity: VisualDensity.compact,
          tooltip: 'Edit',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 16),
        ),
      if (onDelete != null)
        IconButton(
          key: const Key('message-action-delete'),
          visualDensity: VisualDensity.compact,
          tooltip: 'Delete',
          onPressed: onDelete,
          icon: Icon(
            Icons.delete_outline,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      if (onRetry != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Retry send',
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
        ),
      if (onCancel != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove failed send',
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 16),
        ),
    ],
  );
}
