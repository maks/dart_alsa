import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'alsa_generated_bindings.dart' as a;


final timings = [];


void playbackWorker(SendPort replyPort) {
  final requestsPort = ReceivePort();

  final rate = 44100;
  final channels = 2;

  final alsa = Alsa(rate, channels);

  final timer = Stopwatch()..start();

  requestsPort.listen((message) {
    if (message is TransferableTypedData) {
      timings.add(timer.elapsedMicroseconds);
      alsa.playBuffer(message.materialize().asUint8List());
    } else if (message is Uint8List) {
      alsa.playBuffer(message);
    } else if (message is String) {
      switch (message) {
        case 'stop':
        print('stopped');
          final file = File('timings.txt');
          for (var i in timings) {
            file.writeAsStringSync('$i\n', mode: FileMode.append);
          }
          print('wrote timings.txt');
          alsa.finishPlayback();
          requestsPort.close();
      }
    } else {
      print('playback Isolate received unexpected data:$message');
    }
  });
  // send the port we're listening on to our parent isolate to receive ongoing requests
  replyPort.send(requestsPort.sendPort);
}

class Alsa {
  // from errno.h
  static const EAGAIN = 11;
  static const EPIPE = 32;

  final alsa = a.ALSA(DynamicLibrary.open('libasound.so.2'));

  Map<String, String> envVars = Platform.environment;
  late final _debug = envVars['DART_ALSA_DEBUG'] != null;

  final pcmHandlePtr = calloc<Pointer<a.snd_pcm_>>();

  late final Pointer<Uint64> framesPtr;

  final int rate;
  final int channels;
  late final int buff_size;

  late Pointer<Uint8> audioFramesBuffer;

  /// Play buffer of audio
  Alsa(
    this.rate,
    this.channels,
  ) {
    // https://github.com/dart-lang/ffigen/issues/72#issuecomment-672060509
    final name = 'default'.toNativeUtf8().cast<Int8>();
    final stream = 0;
    // 0 ia "standard blocking mode";
    // final mode = 0;
    final mode = a.SND_PCM_NONBLOCK;

    final ratePtr = calloc<Uint32>();
    ratePtr.value = rate;

    final dirPtr = Pointer<Int32>.fromAddress(0);
    final tmpPtr = calloc<Uint32>();
    framesPtr = calloc<Uint64>();

    /* Open the PCM device in playback mode */
    final openResult = alsa.snd_pcm_open(pcmHandlePtr, name, stream, mode);
    if (openResult < 0) {
      final errMesg = alsa.snd_strerror(openResult).cast<Utf8>().toDartString();
      throw Exception('ERROR: Can\`t open $name PCM device: $errMesg');
    }

    var paramsPtr = calloc<Pointer<a.snd_pcm_hw_params_>>();

    // Allocate parameters object
    alsa.snd_pcm_hw_params_malloc(paramsPtr);

    alsa.snd_pcm_hw_params_any(pcmHandlePtr.value, paramsPtr.value);

    /* Set parameters */
    var result = 0;
    result = alsa.snd_pcm_hw_params_set_access(pcmHandlePtr.value,
        paramsPtr.value, a.snd_pcm_access_t.SND_PCM_ACCESS_RW_INTERLEAVED);
    if (result < 0) {
      throw Exception("ERROR: Can't set interleaved mode.");
    }
    result = alsa.snd_pcm_hw_params_set_format(pcmHandlePtr.value,
        paramsPtr.value, a.snd_pcm_format_t.SND_PCM_FORMAT_S16_LE);
    if (result < 0) {
      throw Exception("ERROR: Can't set playback format.");
    }
    result = alsa.snd_pcm_hw_params_set_channels(
        pcmHandlePtr.value, paramsPtr.value, channels);
    if (result < 0) {
      throw Exception("ERROR: Can't set number of channels.");
    }
    result = alsa.snd_pcm_hw_params_set_rate_near(
        pcmHandlePtr.value, paramsPtr.value, ratePtr, dirPtr);
    if (result < 0) {
      throw Exception("ERROR: Can't set playback rate.");
    }

    /* Write parameters */
    result = alsa.snd_pcm_hw_params(pcmHandlePtr.value, paramsPtr.value);
    if (result < 0) {
      throw Exception(
          "ERROR: Can't set hardware parameters. ${alsa.snd_strerror(result).cast<Utf8>().toDartString()}");
    }

    /* Resume information */
    final pcmName =
        (alsa.snd_pcm_name(pcmHandlePtr.value)).cast<Utf8>().toDartString();
    _printDebug('PCM name: $pcmName');
    _printDebug(
        'PCM state: ${alsa.snd_pcm_state_name(alsa.snd_pcm_state(pcmHandlePtr.value)).cast<Utf8>().toDartString()}');

    alsa.snd_pcm_hw_params_get_channels(paramsPtr.value, tmpPtr);

    var channelType;
    if (tmpPtr.value == 1) {
      channelType = '(mono)';
    } else if (tmpPtr.value == 2) {
      channelType = '(stereo)';
    }
    _printDebug('channels: ${tmpPtr.value} $channelType');

    alsa.snd_pcm_hw_params_get_rate(paramsPtr.value, tmpPtr, dirPtr);
    _printDebug('rate: ${tmpPtr.value} bps');

    /* Allocate buffer to hold single period */
    alsa.snd_pcm_hw_params_get_period_size(paramsPtr.value, framesPtr, dirPtr);
    _printDebug('period size: ${framesPtr.value}');

    buff_size = framesPtr.value * channels * 2 /* 2 -> sample size */;

    _printDebug('set buffer size: $buff_size');

    alsa.snd_pcm_hw_params_get_period_time(paramsPtr.value, tmpPtr, dirPtr);

    _printDebug('time period: ${tmpPtr.value}');

    audioFramesBuffer = calloc<Uint8>(buff_size);

    calloc.free(paramsPtr);
    calloc.free(ratePtr);
    calloc.free(dirPtr);
  }

  void playBuffer(Uint8List audioData) async {
    // TODO: use nicer way of reading buff_size chunks out of audioData
    final bufferCount = (audioData.length ~/ buff_size);
    for (var j = 0; j <= bufferCount; j++) {
      for (var i = 0; i < buff_size; i++) {
        final index = i + (j * buff_size);
        if (index > audioData.length - 1) {
          break;
        }
        final b = audioData[index];
        audioFramesBuffer[i] = b;
      }

      var frames = -EAGAIN;
      while (frames == -EAGAIN) {
        frames = alsa.snd_pcm_writei(pcmHandlePtr.value,
            audioFramesBuffer.cast<Void>(), framesPtr.value);

        await Future.delayed(Duration(microseconds: 0));
      }

      if (frames == -EPIPE) {
        _printDebug('XRUN.'); // should client get callback for this?
        alsa.snd_pcm_prepare(pcmHandlePtr.value);
      }
      if (frames > 0 && frames != buff_size / 4) {
        _printDebug('Short write, expected: ${buff_size / 4}, wrote: $frames');
      }
      if (frames < 0) {
        throw Exception(
            "ERROR [$frames]. Can't write to PCM device. ${alsa.snd_strerror(frames).cast<Utf8>().toDartString()}");
      }
    }
  }

  void finishPlayback() {
    alsa.snd_pcm_drain(pcmHandlePtr.value);
    alsa.snd_pcm_close(pcmHandlePtr.value);

    calloc.free(audioFramesBuffer);
    calloc.free(pcmHandlePtr);
    calloc.free(framesPtr);
  }

  void _printDebug(String mesg) {
    if (_debug) {
      print(mesg);
    }
  }
}
