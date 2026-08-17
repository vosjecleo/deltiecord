import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/chat_models.dart';

class MobileAvatar extends StatelessWidget {
  const MobileAvatar({
    required this.bytes,
    required this.fallback,
    this.presence,
    this.size = 44,
    super.key,
  });

  final Uint8List? bytes;
  final String fallback;
  final UserPresence? presence;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipOval(
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

String mobilePresenceLabel(UserPresence presence) => switch (presence) {
  UserPresence.online => 'Online',
  UserPresence.away => 'Away',
  UserPresence.offline => 'Offline',
};
