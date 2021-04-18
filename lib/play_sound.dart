import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'alsa_generated_bindings.dart' as a;

const SND_PCM_ACCESS_RW_INTERLEAVED = 3;
const SND_PCM_FORMAT_S16_LE = 2;

final alsa = a.ALSA(DynamicLibrary.open('libasound.so.2'));

void playSound(List<String> args) {
  print('play: ${args[0]}');

  final pcm_handle_ptr = calloc<Pointer<a.snd_pcm_>>();

  // https://github.com/dart-lang/ffigen/issues/72#issuecomment-672060509
  final name = 'default'.toNativeUtf8().cast<Int8>();
  final stream = 0;
  final mode = 0;

  final rate = int.parse(args[0]);
  final channels = int.parse(args[1]);
  final seconds = int.parse(args[2]);

  final ratePtr = calloc<Uint32>();
  ratePtr.value = rate;

  final dirPtr = Pointer<Int32>.fromAddress(0);

  final tmpPtr = calloc<Uint32>();

  final framesPtr = calloc<Uint64>();

  /* Open the PCM device in playback mode */
  final openResult = alsa.snd_pcm_open(pcm_handle_ptr, name, stream, mode);
  if (openResult < 0) {
    final errMesg = alsa.snd_strerror(openResult).cast<Utf8>().toDartString();
    print('ERROR: Can\`t open $name PCM device: $errMesg');
    return;
  }

  var paramsPointer = calloc<Pointer<a.snd_pcm_hw_params_>>();

  // Allocate parameters object
  alsa.snd_pcm_hw_params_malloc(paramsPointer);

  alsa.snd_pcm_hw_params_any(pcm_handle_ptr.value, paramsPointer.value);

  /* Set parameters */

  var result = 0;
  result = alsa.snd_pcm_hw_params_set_access(
      pcm_handle_ptr.value, paramsPointer.value, SND_PCM_ACCESS_RW_INTERLEAVED);
  if (result < 0) {
    throw Exception("ERROR: Can't set interleaved mode.");
  }
  result = alsa.snd_pcm_hw_params_set_format(
      pcm_handle_ptr.value, paramsPointer.value, SND_PCM_FORMAT_S16_LE);
  if (result < 0) {
    throw Exception("ERROR: Can't set format.");
  }
  result = alsa.snd_pcm_hw_params_set_channels(
      pcm_handle_ptr.value, paramsPointer.value, channels);
  if (result < 0) {
    throw Exception("ERROR: Can't set channels number.");
  }
  result = alsa.snd_pcm_hw_params_set_rate_near(
      pcm_handle_ptr.value, paramsPointer.value, ratePtr, dirPtr);
  if (result < 0) {
    throw Exception("ERROR: Can't set rate.");
  }

  /* Write parameters */
  result = alsa.snd_pcm_hw_params(pcm_handle_ptr.value, paramsPointer.value);
  if (result < 0) {
    print(
      "ERROR: Can't set harware parameters. ${alsa.snd_strerror(result).cast<Utf8>().toDartString()}",
    );
  }

  /* Resume information */
  final pcmName =
      (alsa.snd_pcm_name(pcm_handle_ptr.value)).cast<Utf8>().toDartString();
  print('PCM name: $pcmName');

  print(
      'PCM state: ${alsa.snd_pcm_state_name(alsa.snd_pcm_state(pcm_handle_ptr.value)).cast<Utf8>().toDartString()}');

  alsa.snd_pcm_hw_params_get_channels(paramsPointer.value, tmpPtr);

  var channelType;
  if (tmpPtr.value == 1) {
    channelType = '(mono)';
  } else if (tmpPtr.value == 2) {
    channelType = '(stereo)';
  }

  print('channels: ${tmpPtr.value} $channelType');

  alsa.snd_pcm_hw_params_get_rate(paramsPointer.value, tmpPtr, dirPtr);
  print('rate: ${tmpPtr.value} bps');

  print('seconds: $seconds');

  /* Allocate buffer to hold single period */
  alsa.snd_pcm_hw_params_get_period_size(
      paramsPointer.value, framesPtr, dirPtr);

  final buff_size = 8 * channels * 2 /* 2 -> sample size */;
  final buff = calloc<Uint8>(buff_size);

  alsa.snd_pcm_hw_params_get_period_time(paramsPointer.value, tmpPtr, dirPtr);

  for (var loops = (seconds * 1000000) / tmpPtr.value; loops > 0; loops--) {
    for (var i = 0; i < buff_size; i++) {
      final b = stdin.readByteSync();
      if (b != -1) {
        buff[i] = b;
      } else {
        print('end of input file');
      }
    }

    var pcm = alsa.snd_pcm_writei(
        pcm_handle_ptr.value, buff.cast<Void>(), framesPtr.value);

    final EPIPE = 32;
    if (pcm == -EPIPE) {
      print('XRUN.');
      alsa.snd_pcm_prepare(pcm_handle_ptr.value);
    } else if (pcm < 0) {
      print(
          "ERROR. Can't write to PCM device. ${alsa.snd_strerror(pcm).cast<Utf8>().toDartString()}");
    }
  }

  alsa.snd_pcm_drain(pcm_handle_ptr.value);
  alsa.snd_pcm_close(pcm_handle_ptr.value);
  calloc.free(buff);

  exit(0);
}
