import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AccentColorPicker extends StatefulWidget {
  const AccentColorPicker({
    required this.color,
    required this.onChanged,
    super.key,
  });

  final int color;
  final ValueChanged<int> onChanged;

  @override
  State<AccentColorPicker> createState() => _AccentColorPickerState();
}

class _AccentColorPickerState extends State<AccentColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.color));
  late final TextEditingController _hex = TextEditingController(
    text: _hexValue(widget.color),
  );

  @override
  void didUpdateWidget(covariant AccentColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color == widget.color) return;
    _hsv = HSVColor.fromColor(Color(widget.color));
    final value = _hexValue(widget.color);
    if (_hex.text != value) _hex.text = value;
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv) {
    final color = hsv.toColor().withValues(alpha: 1);
    setState(() {
      _hsv = hsv;
      _hex.text = _hexValue(color.toARGB32());
    });
    widget.onChanged(color.toARGB32());
  }

  void _pickFromWheel(Offset local, double size) {
    final center = Offset(size / 2, size / 2);
    final delta = local - center;
    final radius = size / 2;
    final saturation = (delta.distance / radius).clamp(0.0, 1.0);
    final hue = (atan2(delta.dy, delta.dx) * 180 / pi + 360) % 360;
    _setHsv(_hsv.withHue(hue).withSaturation(saturation));
  }

  void _applyHex(String raw) {
    final normalized = raw.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    final color = Color(0xff000000 | int.parse(normalized, radix: 16));
    _setHsv(HSVColor.fromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    const wheelSize = 184.0;
    return Wrap(
      spacing: 22,
      runSpacing: 14,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GestureDetector(
          key: const Key('accent-colour-wheel'),
          onPanDown: (event) => _pickFromWheel(event.localPosition, wheelSize),
          onPanUpdate: (event) =>
              _pickFromWheel(event.localPosition, wheelSize),
          child: CustomPaint(
            size: const Size.square(wheelSize),
            painter: _ColourWheelPainter(_hsv),
          ),
        ),
        SizedBox(
          width: 270,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _hsv.toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const Key('accent-hex-field'),
                      controller: _hex,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F#]'),
                        ),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Hex colour',
                        hintText: '#6975D9',
                      ),
                      onChanged: _applyHex,
                      onSubmitted: _applyHex,
                      onEditingComplete: () => _applyHex(_hex.text),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Brightness — ${(_hsv.value * 100).round()}%'),
              Slider(
                value: _hsv.value,
                min: 0.15,
                max: 1,
                onChanged: (value) => _setHsv(_hsv.withValue(value)),
              ),
              const Text(
                'Drag around the wheel for hue and saturation, or enter an '
                'exact six-digit hex value.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _hexValue(int color) =>
      '#${(color & 0x00ffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _ColourWheelPainter extends CustomPainter {
  const _ColourWheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Color(0xffff00ff),
            Colors.red,
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00ffffff)],
        ).createShader(rect),
    );
    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }
    final angle = hsv.hue * pi / 180;
    final marker =
        center + Offset(cos(angle), sin(angle)) * radius * hsv.saturation;
    canvas.drawCircle(marker, 7, Paint()..color = hsv.toColor());
    canvas.drawCircle(
      marker,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ColourWheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}
