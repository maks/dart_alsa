import 'dart:math';

void main(List<String> args) {
  final osc = DartSineOscillator(44100, 440);
  final next = osc.next();
  print('$next');
}

/// Port of petersalomonsen AssemblyScript sine oscillator
///
/// ref: https://github.com/petersalomonsen/javascriptmusic/blob/master/wasmaudioworklet/synth1/assembly/synth/sineoscillator.class.ts
class DartSineOscillator {
  int position = 0;
  final double frequency;
  final sampleRate;

  DartSineOscillator(this.sampleRate, this.frequency);

  double next() {
    final ret = sin(pi * 2 * (position) / (1 << 16));
    position =
        (((position) + (frequency / sampleRate) * 0x10000).toInt()) & 0xffff;

    return ret;
  }
}
