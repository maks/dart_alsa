# Dart FFI Binding to the ALSA sound library.

## Regenerating the Dart ffi binding code

Settings for ffigen are in `pubspec.yaml`, to regenerate the binding code run:

`dart run ffigen`


## Testing

check wav file properties:
`mediainfo filename.wav`

ref: https://mediaarea.net/en/MediaInfo

run example:
`dart example/playsound.dart 44100 2 < refs/test1.wav`


## Acknowledgements

My thanks to [Morten Boye Mortensen](https://github.com/mortenboye) whose use of ALSA via ffigen for Linux support in the [Flutter Midi Command](https://pub.dev/packages/flutter_midi_command) Dart package served as the inspiration for this package.

Initial playback implementation based on 
[sample code by Alessandro Ghedini](https://gist.github.com/ghedo/963382/815c98d1ba0eda1b486eb9d80d9a91a81d995283).

