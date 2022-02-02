import 'dart:io';
import 'dart:typed_data';

import 'package:dart_alsa/play_audio.dart';

void main(List<String> args) {
  if (args.length != 2) {
    print('usage: play_wave <samplerate> <channels>');
    exit(1);
  }
  final rate = int.parse(args[0]);
  final channels = int.parse(args[1]);

  final buffer = <int>[];

  var b = 0;
  while (b != -1) {
    b = stdin.readByteSync();
    buffer.add(b);
  }
  print('buffer len: ${buffer.length}');
  final alsa = Alsa(rate, channels);
  alsa.playBuffer(Uint8List.fromList(buffer));

  exit(0);
}
