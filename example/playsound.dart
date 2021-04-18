import 'dart:io';

import 'package:dart_alsa/play_sound.dart';

void main(List<String> args) {
  final rate = int.parse(args[0]);
  final channels = int.parse(args[1]);
  final seconds = int.parse(args[2]);

  play(stdin, rate, channels, seconds);

  exit(0);
}
