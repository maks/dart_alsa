import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_alsa/play_audio.dart';

import 'osc.dart';

void main(List<String> args) async {
  // if (args.length != 2) {
  //   print('usage: play_wave <samplerate> <channels>');
  //   exit(1);
  // }
  // final rate = int.parse(args[0]);
  // final channels = int.parse(args[1]);

  final rate = 44100;
  final channels = 2;

  const bits = 16;

  const bufferFrames = 4096;
  final buffer = Uint8List(bits ~/ 8 * channels * bufferFrames);

  const volume = 0.5;

  final osc = DartSineOscillator(rate, 440);

  final isolateResponsePort = ReceivePort();
  final playbackIsolate = await Isolate.spawn<SendPort>(
      playbackWorker, isolateResponsePort.sendPort);

  final isolateExitPort = ReceivePort();
  playbackIsolate.addOnExitListener(isolateExitPort.sendPort);
  isolateExitPort.listen((message) {
    print('playback isolate exited');
    isolateResponsePort.close();
    isolateExitPort.close();
  });

  final completer = Completer<SendPort>();

  final isoSubcription = isolateResponsePort.listen((message) {
    if (message is SendPort) {
      final mainToIsolateStream = message;
      completer.complete(mainToIsolateStream);
    } else {
      print('unexpected message from isolate:$message');
    }
  });

  final toIsolateSendPort = await completer.future;

  ProcessSignal.sigint.watch().listen((signal) async {
    print('sigint disconnecting');
    toIsolateSendPort.send('stop');
    await isoSubcription.cancel();

    await Future.delayed(Duration(seconds: 2));
    exit(0);
  });

  while (true) {
    for (var i = 0; i < bufferFrames; i++) {
      final sample = (osc.next() * volume * 32768.0).toInt();
      // Left = Right.
      buffer[4 * i] = buffer[4 * i + 2] = sample & 0xff;
      buffer[4 * i + 1] = buffer[4 * i + 3] = (sample >> 8) & 0xff;
    }
    toIsolateSendPort.send(TransferableTypedData.fromList([buffer]));

    // need this not to stave event loop and allow sigint event to be processed
    await Future.delayed(Duration(microseconds: 0));
  }

 
}
