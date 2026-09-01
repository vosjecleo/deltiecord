part of 'chat_shell.dart';

class _RichComposer extends StatefulWidget {
  const _RichComposer({
    required this.controller,
    required this.focusNode,
    required this.roomName,
    required this.enabled,
    required this.onSend,
    required this.onAttach,
    required this.onGif,
    required this.onPasteImage,
    required this.pendingAttachments,
    required this.onRemoveAttachment,
    required this.onToggleAttachmentSpoiler,
    required this.mentionSuggestions,
    required this.mentionSelectionIndex,
    required this.onMentionSelected,
    required this.onMentionSelectionChanged,
    required this.sendWithCtrlEnter,
    required this.maxHeight,
    super.key,
  });

  final QuillController controller;
  final FocusNode focusNode;
  final String roomName;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onGif;
  final Future<bool> Function() onPasteImage;
  final List<AttachmentDraft> pendingAttachments;
  final ValueChanged<int> onRemoveAttachment;
  final ValueChanged<int> onToggleAttachmentSpoiler;
  final List<MentionSuggestion> mentionSuggestions;
  final int mentionSelectionIndex;
  final ValueChanged<String> onMentionSelected;
  final ValueChanged<int> onMentionSelectionChanged;
  final bool sendWithCtrlEnter;
  final double maxHeight;

  @override
  State<_RichComposer> createState() => _RichComposerState();
}

class _MentionPicker extends StatelessWidget {
  const _MentionPicker({
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MentionSuggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Material(
      color: context.deltiecord.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.deltiecord.divider),
        borderRadius: const BorderRadius.vertical(
          top: DeltiecordCorners.corner,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 210),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            return ListTile(
              dense: true,
              selected: index == selectedIndex,
              selectedTileColor: context.deltiecord.hover,
              title: Text(suggestion.displayName),
              subtitle: Text(suggestion.isRoom ? 'Room' : suggestion.matrixId),
              onTap: () => onSelected(suggestion.matrixId),
            );
          },
        ),
      ),
    ),
  );
}

class _RichComposerState extends State<_RichComposer> {
  final _scrollController = ScrollController();
  final _emojiOverlay = OverlayPortalController();
  final _emojiAnchor = LayerLink();
  List<EmojiEntry> _emojiMatches = const [];
  int _emojiSelection = 0;
  int? _emojiStart;
  int _emojiGeneration = 0;
  int _visibleLineCount = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateEmojiCompletion);
  }

  void _updateEmojiCompletion() {
    final text = widget.controller.document.toPlainText();
    final lineCount = max(
      1,
      '\n'
              .allMatches(
                text.endsWith('\n') ? text.substring(0, text.length - 1) : text,
              )
              .length +
          1,
    );
    if (lineCount != _visibleLineCount) {
      setState(() => _visibleLineCount = lineCount);
    }
    final cursor = widget.controller.selection.extentOffset.clamp(
      0,
      text.length,
    );
    final completion = findEmojiCompletion(text, cursor);
    if (completion == null) {
      _clearEmojiCompletion();
      return;
    }
    if (completion.closed) {
      final query = completion.query;
      final start = completion.start;
      final familiar = EmojiRepository.instance.familiarEmoji(query);
      if (familiar != null) {
        widget.controller.replaceText(
          start,
          cursor - start,
          familiar,
          TextSelection.collapsed(offset: start + familiar.length),
        );
        return;
      }
      final generation = ++_emojiGeneration;
      EmojiRepository.instance.exactAlias(query).then((entry) {
        if (!mounted || generation != _emojiGeneration || entry == null) return;
        widget.controller.replaceText(
          start,
          cursor - start,
          entry.emoji,
          TextSelection.collapsed(offset: start + entry.emoji.length),
        );
      });
      return;
    }
    final start = completion.start;
    final query = completion.query;
    final generation = ++_emojiGeneration;
    final familiarMatches = EmojiRepository.instance.familiarMatches(query);
    if (familiarMatches.isNotEmpty) {
      setState(() {
        _emojiStart = start;
        _emojiMatches = familiarMatches;
        _emojiSelection = 0;
      });
      _syncEmojiOverlay();
    }
    EmojiRepository.instance.search(query, limit: 3).then((matches) {
      if (!mounted || generation != _emojiGeneration) return;
      setState(() {
        _emojiStart = start;
        _emojiMatches = matches;
        _emojiSelection = matches.isEmpty
            ? 0
            : _emojiSelection.clamp(0, matches.length - 1);
      });
      _syncEmojiOverlay();
    });
  }

  void _syncEmojiOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_emojiMatches.isEmpty) {
        if (_emojiOverlay.isShowing) _emojiOverlay.hide();
      } else if (!_emojiOverlay.isShowing) {
        _emojiOverlay.show();
      }
    });
  }

  void _clearEmojiCompletion() {
    _emojiGeneration++;
    if (_emojiMatches.isEmpty && _emojiStart == null) return;
    setState(() {
      _emojiMatches = const [];
      _emojiStart = null;
      _emojiSelection = 0;
    });
    _syncEmojiOverlay();
  }

  void _acceptEmoji(EmojiEntry entry) {
    final start = _emojiStart;
    if (start == null) return;
    final end = widget.controller.selection.extentOffset;
    widget.controller.replaceText(
      start,
      end - start,
      entry.emoji,
      TextSelection.collapsed(offset: start + entry.emoji.length),
    );
    _clearEmojiCompletion();
    widget.focusNode.requestFocus();
  }

  void _insertEmoji(String emoji) {
    final selection = widget.controller.selection;
    final start = selection.start < 0
        ? widget.controller.document.length - 1
        : selection.start;
    final length = selection.isValid ? selection.end - selection.start : 0;
    widget.controller.replaceText(
      start,
      length,
      emoji,
      TextSelection.collapsed(offset: start + emoji.length),
    );
    widget.focusNode.requestFocus();
  }

  Future<void> showEmojiPicker() async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) => const EmojiPickerDialog(),
    );
    if (emoji != null) _insertEmoji(emoji);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateEmojiCompletion);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controlHeight = _composerControlHeightFor(context);
    final editorHeight = _composerEditorHeightFor(context);
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(DeltiecordTypeScale.normal) *
        1.2;
    final expandedEditorHeight = min(
      widget.maxHeight,
      editorHeight + ((_visibleLineCount - 1) * lineHeight),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: OverlayPortal(
        controller: _emojiOverlay,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _emojiAnchor,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(56, -4),
          child: UnconstrainedBox(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 280,
              child: Material(
                key: const Key('emoji-completion-popup'),
                elevation: 8,
                color: context.deltiecord.surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: context.deltiecord.divider),
                  borderRadius: DeltiecordCorners.borderRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The strongest match sits nearest the input so accepting
                    // the default result feels spatially connected to typing.
                    for (
                      var index = _emojiMatches.length - 1;
                      index >= 0;
                      index--
                    )
                      InkWell(
                        key: Key('emoji-completion-result-$index'),
                        onTap: () => _acceptEmoji(_emojiMatches[index]),
                        child: Container(
                          color: index == _emojiSelection
                              ? context.deltiecord.hover
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: _emojiMatches[index].emoji,
                                  style: TextStyle(
                                    fontFamily: context.deltiecordEmojiFont,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      '  :${_emojiMatches[index].aliases.firstOrNull ?? _emojiMatches[index].name}:',
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _emojiAnchor,
          child: ColoredBox(
            color: context.deltiecord.panel,
            child: Padding(
              key: const Key('message-composer-panel'),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: _bottomPanelVerticalInset,
              ),
              child: Container(
                key: const Key('message-composer-island'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  // The one-pixel outline replaces one pixel of the existing
                  // inset on each edge, preserving shared bottom geometry.
                  vertical: _composerIslandVerticalInset - 1,
                ),
                decoration: BoxDecoration(
                  color: context.deltiecord.island,
                  border: Border.all(color: Colors.black, width: 1),
                  borderRadius: DeltiecordCorners.borderRadius,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 40,
                      height: controlHeight,
                      child: PopupMenuButton<String>(
                        tooltip: 'Add content',
                        enabled: widget.enabled,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.add_circle_outline,
                          size: 25,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onSelected: (action) {
                          switch (action) {
                            case 'file':
                              widget.onAttach();
                            case 'emoji':
                              showEmojiPicker();
                            case 'gif':
                              widget.onGif();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'file',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.insert_drive_file_outlined),
                              title: Text('Add file'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'emoji',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.emoji_emotions_outlined),
                              title: Text('Emoji'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'gif',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.gif_box_outlined),
                              title: Text('Sticker / GIF'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: context.deltiecord.island,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.pendingAttachments.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < widget.pendingAttachments.length;
                                      index++
                                    )
                                      _PendingAttachmentTile(
                                        attachment:
                                            widget.pendingAttachments[index],
                                        onRemove: () =>
                                            widget.onRemoveAttachment(index),
                                        onToggleSpoiler: () => widget
                                            .onToggleAttachmentSpoiler(index),
                                      ),
                                  ],
                                ),
                              ),
                            Flexible(
                              fit: FlexFit.loose,
                              child: DefaultTextStyle.merge(
                                style: const TextStyle(
                                  fontSize: DeltiecordTypeScale.normal,
                                ),
                                child: SizedBox(
                                  height: expandedEditorHeight,
                                  child: QuillEditor(
                                    controller: widget.controller,
                                    focusNode: widget.focusNode,
                                    scrollController: _scrollController,
                                    config: QuillEditorConfig(
                                      autoFocus: false,
                                      minHeight: editorHeight,
                                      maxHeight: expandedEditorHeight,
                                      customStyles: const DefaultStyles(
                                        paragraph: DefaultTextBlockStyle(
                                          TextStyle(
                                            fontSize:
                                                DeltiecordTypeScale.normal,
                                            height: 1.2,
                                          ),
                                          HorizontalSpacing.zero,
                                          VerticalSpacing.zero,
                                          VerticalSpacing.zero,
                                          null,
                                        ),
                                        placeHolder: DefaultTextBlockStyle(
                                          TextStyle(
                                            fontSize:
                                                DeltiecordTypeScale.normal,
                                            height: 1.2,
                                            color: Color(0x99989aa5),
                                          ),
                                          HorizontalSpacing.zero,
                                          VerticalSpacing.zero,
                                          VerticalSpacing.zero,
                                          null,
                                        ),
                                      ),
                                      // Keep the compact composer while seating its text
                                      // cleanly alongside the attachment and send controls.
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 7,
                                      ),
                                      placeholder:
                                          'Message #${widget.roomName}',
                                      // ignore: experimental_member_use
                                      onKeyPressed: (event, _) {
                                        if (event is KeyDownEvent &&
                                            _emojiMatches.isNotEmpty) {
                                          if (event.logicalKey ==
                                              LogicalKeyboardKey.tab) {
                                            setState(
                                              () => _emojiSelection =
                                                  (_emojiSelection + 1) %
                                                  _emojiMatches.length,
                                            );
                                            return KeyEventResult.handled;
                                          }
                                          if (event.logicalKey ==
                                              LogicalKeyboardKey.enter) {
                                            _acceptEmoji(
                                              _emojiMatches[_emojiSelection],
                                            );
                                            return KeyEventResult.handled;
                                          }
                                          if (event.logicalKey ==
                                              LogicalKeyboardKey.escape) {
                                            _clearEmojiCompletion();
                                            return KeyEventResult.handled;
                                          }
                                        }
                                        if (event is KeyDownEvent &&
                                            event.logicalKey ==
                                                LogicalKeyboardKey.keyV &&
                                            (HardwareKeyboard
                                                    .instance
                                                    .isControlPressed ||
                                                HardwareKeyboard
                                                    .instance
                                                    .isMetaPressed)) {
                                          unawaited(widget.onPasteImage());
                                          return KeyEventResult.ignored;
                                        }
                                        if (event is KeyDownEvent &&
                                            widget
                                                .mentionSuggestions
                                                .isNotEmpty) {
                                          if (event.logicalKey ==
                                              LogicalKeyboardKey.arrowDown) {
                                            widget.onMentionSelectionChanged(
                                              (widget.mentionSelectionIndex +
                                                      1) %
                                                  widget
                                                      .mentionSuggestions
                                                      .length,
                                            );
                                            return KeyEventResult.handled;
                                          }
                                          if (event.logicalKey ==
                                              LogicalKeyboardKey.arrowUp) {
                                            widget.onMentionSelectionChanged(
                                              (widget.mentionSelectionIndex -
                                                      1) %
                                                  widget
                                                      .mentionSuggestions
                                                      .length,
                                            );
                                            return KeyEventResult.handled;
                                          }
                                          if (event.logicalKey ==
                                                  LogicalKeyboardKey.enter &&
                                              !HardwareKeyboard
                                                  .instance
                                                  .isShiftPressed) {
                                            widget.onMentionSelected(
                                              widget
                                                  .mentionSuggestions[widget
                                                      .mentionSelectionIndex]
                                                  .matrixId,
                                            );
                                            return KeyEventResult.handled;
                                          }
                                        }
                                        if (event is KeyDownEvent &&
                                            event.logicalKey ==
                                                LogicalKeyboardKey.enter &&
                                            !HardwareKeyboard
                                                .instance
                                                .isShiftPressed &&
                                            (widget.sendWithCtrlEnter ==
                                                HardwareKeyboard
                                                    .instance
                                                    .isControlPressed)) {
                                          widget.onSend();
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: controlHeight,
                      child: IconButton(
                        tooltip: 'Send',
                        padding: EdgeInsets.zero,
                        onPressed: widget.enabled ? widget.onSend : null,
                        icon: Icon(
                          Icons.send,
                          size: 25,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingAttachmentTile extends StatelessWidget {
  const _PendingAttachmentTile({
    required this.attachment,
    required this.onRemove,
    required this.onToggleSpoiler,
  });

  final AttachmentDraft attachment;
  final VoidCallback onRemove;
  final VoidCallback onToggleSpoiler;

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(position);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'spoiler',
          child: ListTile(
            dense: true,
            leading: Icon(
              attachment.spoiler
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            title: Text(attachment.spoiler ? 'Remove spoiler' : 'Spoiler'),
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.close),
            title: Text('Remove attachment'),
          ),
        ),
      ],
    );
    if (action == 'spoiler') onToggleSpoiler();
    if (action == 'remove') onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final isVideo = attachment.mimeType.startsWith('video/');
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showMenu(context, details.globalPosition),
      child: Tooltip(
        message: '${attachment.name}\nRight-click for options',
        child: Container(
          width: 72,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.deltiecord.elevated,
            border: Border.all(
              color: attachment.spoiler
                  ? Theme.of(context).colorScheme.primary
                  : context.deltiecord.divider,
            ),
            borderRadius: DeltiecordCorners.borderRadius,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isImage)
                Image.memory(attachment.bytes, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVideo
                          ? Icons.video_file_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 23,
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: DeltiecordTypeScale.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              if (attachment.spoiler)
                const ColoredBox(
                  color: Color(0xcc17181c),
                  child: Center(
                    child: Icon(Icons.visibility_off_outlined, size: 20),
                  ),
                ),
              Positioned(
                right: 1,
                top: 1,
                child: SizedBox.square(
                  dimension: 20,
                  child: IconButton.filledTonal(
                    padding: EdgeInsets.zero,
                    tooltip: 'Remove',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    required this.label,
    required this.body,
    required this.onCancel,
  });

  final String label;
  final String body;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
    color: context.deltiecord.surface,
    padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
    child: Row(
      children: [
        const Icon(Icons.subdirectory_arrow_right, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: DeltiecordTypeScale.normal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                body.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: DeltiecordTypeScale.normal,
                  color: Color(0xff989aa5),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cancel',
          visualDensity: VisualDensity.compact,
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
}
