import 'package:flutter/material.dart';

import 'deltiecord_theme.dart';

/// A fixed-height typing footer so appearing activity never shifts the
/// timeline or composer. The dots pulse in sequence without rebuilding chat.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({required this.names, super.key});

  final List<String> names;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.names.isEmpty != widget.names.isEmpty) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.names.isEmpty) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.names.isNotEmpty;
    return Semantics(
      label: visible ? typingLabel(widget.names) : null,
      child: SizedBox(
        key: const Key('typing-indicator'),
        height: 28,
        child: DecoratedBox(
          key: const Key('typing-indicator-gradient'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.deltiecord.background.withValues(alpha: 0),
                context.deltiecord.background.withValues(alpha: 0.96),
              ],
            ),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: visible ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Row(
                      children: [
                        for (var index = 0; index < 3; index++) ...[
                          Opacity(
                            opacity: _dotOpacity(_controller.value, index),
                            child: Text(
                              '•',
                              style: TextStyle(
                                color: context.deltiecord.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (index < 2) const SizedBox(width: 1),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      visible ? typingLabel(widget.names) : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DeltiecordTypeScale.small,
                        color: context.deltiecord.muted,
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

  double _dotOpacity(double progress, int index) {
    final shifted = (progress - index * 0.18) % 1.0;
    if (shifted < 0.22) return 0.25 + (shifted / 0.22) * 0.75;
    if (shifted < 0.44) return 1 - ((shifted - 0.22) / 0.22) * 0.75;
    return 0.25;
  }
}

String typingLabel(List<String> names) => switch (names.length) {
  0 => '',
  1 => '${names.first} is typing',
  2 => '${names.first} and ${names[1]} are typing',
  3 => '${names.first}, ${names[1]} and ${names[2]} are typing',
  _ => 'Several people are typing',
};
