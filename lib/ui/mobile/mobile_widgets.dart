import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/chat_models.dart';

class MobileAvatar extends StatelessWidget {
  const MobileAvatar({
    required this.bytes,
    required this.fallback,
    this.presence,
    this.size = 44,
    this.borderColor,
    this.speaking = false,
    this.square = false,
    super.key,
  });

  final Uint8List? bytes;
  final String fallback;
  final UserPresence? presence;
  final double size;
  final Color? borderColor;
  final bool speaking;
  final bool square;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
            padding: EdgeInsets.all(borderColor == null ? 0 : 2),
            decoration: BoxDecoration(
              shape: square ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: square ? BorderRadius.circular(11) : null,
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor!, width: 2),
            ),
            child: Container(
              padding: EdgeInsets.all(speaking ? 2 : 0),
              decoration: BoxDecoration(
                shape: square ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: square ? BorderRadius.circular(9) : null,
                border: speaking
                    ? Border.all(color: const Color(0xff23c483), width: 2)
                    : null,
              ),
              child: ClipPath(
                clipper: square ? _SquarcleClipper() : const _OvalClipper(),
                child: bytes == null
                    ? ColoredBox(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Center(
                          child: Text(
                            fallback.isEmpty ? '?' : fallback[0].toUpperCase(),
                            style: TextStyle(fontSize: size * 0.38),
                          ),
                        ),
                      )
                    : Image.memory(
                        bytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
            ),
          ),
        ),
        if (presence case final presence?)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.27,
              height: size * 0.27,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (presence) {
                  UserPresence.online => const Color(0xff23c483),
                  UserPresence.away => const Color(0xffe3a53a),
                  UserPresence.doNotDisturb => const Color(0xffe5484d),
                  UserPresence.offline => const Color(0xff70737d),
                },
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _OvalClipper extends CustomClipper<Path> {
  const _OvalClipper();

  @override
  Path getClip(Size size) => Path()..addOval(Offset.zero & size);

  @override
  bool shouldReclip(_OvalClipper oldClipper) => false;
}

class _SquarcleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(9)),
    );

  @override
  bool shouldReclip(_SquarcleClipper oldClipper) => false;
}

String mobilePresenceLabel(UserPresence presence) => switch (presence) {
  UserPresence.online => 'Online',
  UserPresence.away => 'Away',
  UserPresence.doNotDisturb => 'Do not disturb',
  UserPresence.offline => 'Offline',
};
