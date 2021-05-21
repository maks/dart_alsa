import 'dart:io';

import 'package:dart_alsa/play_sound.dart';

void main(List<String> args) {
  final rate = int.parse(args[0]);
  final channels = int.parse(args[1]);

  final buffer = <int>[];

  for (var i = 0; i < (channels * rate); i++) {
    buffer.add(stdin.readByteSync());
  }

  playBuffer(buffer, rate, channels);

  exit(0);
}
