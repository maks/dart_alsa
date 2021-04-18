import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'alsa_generated_bindings.dart' as a;

const SND_PCM_ACCESS_RW_INTERLEAVED = 3;
const SND_PCM_FORMAT_S16_LE = 2;

final alsa = a.ALSA(DynamicLibrary.open('libasound.so.2'));

final _debug = false;

Future<void> play(
  Stream<List<int>> audioStream,
  int rate,
  int channels,
  int seconds,
) async {
  final pcmHandlePtr = calloc<Pointer<a.snd_pcm_>>();

  // https://github.com/dart-lang/ffigen/issues/72#issuecomment-672060509
  final name = 'default'.toNativeUtf8().cast<Int8>();
  final stream = 0;
  final mode = 0;

  final ratePtr = calloc<Uint32>();
  ratePtr.value = rate;

  final dirPtr = Pointer<Int32>.fromAddress(0);

  final tmpPtr = calloc<Uint32>();

  final framesPtr = calloc<Uint64>();

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
  result = alsa.snd_pcm_hw_params_set_access(
      pcmHandlePtr.value, paramsPtr.value, SND_PCM_ACCESS_RW_INTERLEAVED);
  if (result < 0) {
    throw Exception("ERROR: Can't set interleaved mode.");
  }
  result = alsa.snd_pcm_hw_params_set_format(
      pcmHandlePtr.value, paramsPtr.value, SND_PCM_FORMAT_S16_LE);
  if (result < 0) {
    throw Exception("ERROR: Can't set format.");
  }
  result = alsa.snd_pcm_hw_params_set_channels(
      pcmHandlePtr.value, paramsPtr.value, channels);
  if (result < 0) {
    throw Exception("ERROR: Can't set channels number.");
  }
  result = alsa.snd_pcm_hw_params_set_rate_near(
      pcmHandlePtr.value, paramsPtr.value, ratePtr, dirPtr);
  if (result < 0) {
    throw Exception("ERROR: Can't set rate.");
  }

  /* Write parameters */
  result = alsa.snd_pcm_hw_params(pcmHandlePtr.value, paramsPtr.value);
  if (result < 0) {
    throw Exception(
        "ERROR: Can't set harware parameters. ${alsa.snd_strerror(result).cast<Utf8>().toDartString()}");
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
  _printDebug('seconds: $seconds');

  /* Allocate buffer to hold single period */
  alsa.snd_pcm_hw_params_get_period_size(paramsPtr.value, framesPtr, dirPtr);

  final buff_size = framesPtr.value * channels * 2 /* 2 -> sample size */;
  final buff = calloc<Uint8>(buff_size);

  alsa.snd_pcm_hw_params_get_period_time(paramsPtr.value, tmpPtr, dirPtr);

  _printDebug('time period: ${tmpPtr.value}');

  for (var loops = (seconds * 1000000) / tmpPtr.value; loops > 0; loops--) {
    for (var i = 0; i < buff_size; i++) {
      final b = stdin.readByteSync();
      if (b != -1) {
        buff[i] = b;
      } else {
        _printDebug('end of input file');
        loops = 0; //stop playback looping
        break;
      }
    }
    var pcm = alsa.snd_pcm_writei(
        pcmHandlePtr.value, buff.cast<Void>(), framesPtr.value);

    final EPIPE = 32;
    if (pcm == -EPIPE) {
      _printDebug('XRUN.'); // should client get callback for this?
      alsa.snd_pcm_prepare(pcmHandlePtr.value);
    } else if (pcm < 0) {
      throw Exception(
          "ERROR. Can't write to PCM device. ${alsa.snd_strerror(pcm).cast<Utf8>().toDartString()}");
    }
  }

  alsa.snd_pcm_drain(pcmHandlePtr.value);
  alsa.snd_pcm_close(pcmHandlePtr.value);
  calloc.free(buff);
  calloc.free(pcmHandlePtr);
  calloc.free(paramsPtr);
  calloc.free(ratePtr);
  calloc.free(framesPtr);
  calloc.free(dirPtr);
}

void _printDebug(String mesg) {
  if (_debug) {
    print(mesg);
  }
}
