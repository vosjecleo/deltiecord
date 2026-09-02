import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

class PollCard extends StatefulWidget {
  const PollCard({required this.backend, required this.message, super.key});

  final ChatBackend backend;
  final ChatMessage message;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final _selected = <String>{};
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final poll = widget.message.poll!;
    final total = poll.answers.fold<int>(
      0,
      (sum, answer) => sum + answer.votes,
    );
    return Container(
      key: ValueKey('poll-${widget.message.id}'),
      constraints: const BoxConstraints(maxWidth: 500),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.deltiecord.elevated,
        borderRadius: DeltiecordCorners.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            poll.question,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          for (final answer in poll.answers)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: InkWell(
                onTap: poll.ended || _submitting
                    ? null
                    : () async {
                        if (poll.maxSelections <= 1) {
                          setState(() {
                            _selected
                              ..clear()
                              ..add(answer.id);
                          });
                          await _submit();
                        } else {
                          setState(() {
                            if (_selected.contains(answer.id)) {
                              _selected.remove(answer.id);
                            } else if (_selected.length < poll.maxSelections) {
                              _selected.add(answer.id);
                            }
                          });
                        }
                      },
                borderRadius: DeltiecordCorners.borderRadius,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: answer.selectedByMe || _selected.contains(answer.id)
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.18)
                        : context.deltiecord.input,
                    borderRadius: DeltiecordCorners.borderRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        poll.maxSelections > 1
                            ? (_selected.contains(answer.id)
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank)
                            : (answer.selectedByMe ||
                                      _selected.contains(answer.id)
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(answer.text)),
                      if (poll.disclosed || poll.ended)
                        Text('${answer.votes}')
                      else
                        const Icon(Icons.visibility_off_outlined, size: 15),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${poll.disclosed || poll.ended ? '$total vote${total == 1 ? '' : 's'}' : 'Results hidden'}${poll.ended ? ' · Ended' : ''}',
                  style: TextStyle(
                    color: context.deltiecord.muted,
                    fontSize: 12,
                  ),
                ),
              ),
              if (poll.maxSelections > 1 && !poll.ended)
                TextButton(
                  onPressed: _selected.isEmpty || _submitting ? null : _submit,
                  child: const Text('Vote'),
                ),
              if (widget.message.own && !poll.ended)
                TextButton(
                  onPressed: () => widget.backend.endPoll(widget.message.id),
                  child: const Text('End poll'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await widget.backend.answerPoll(widget.message.id, _selected.toList());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
