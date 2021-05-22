import 'dart:io';
import 'dart:typed_data';

import 'package:dart_alsa/play_audio.dart';

void main(List<String> args) {
  final rate = int.parse(args[0]);
  final channels = int.parse(args[1]);

  final buffer = <int>[];

  var b = 0;
  while (b != -1) {
    b = stdin.readByteSync();
    buffer.add(b);
  }
  print('buffer len: ${buffer.length}');

  playBuffer(Uint8List.fromList(buffer), rate, channels);

  exit(0);
}
