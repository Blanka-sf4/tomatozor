import 'dart:typed_data';

import 'package:bpm_detector_app/history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodeWav : en-tête RIFF correct et données intactes', () {
    final pcm = Int16List.fromList([0, 1000, -1000, 32767, -32768]);
    final wav = encodeWav(pcm, 44100);
    expect(wav.length, 44 + pcm.length * 2);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    final bd = ByteData.sublistView(wav);
    expect(bd.getUint32(24, Endian.little), 44100);
    expect(bd.getUint16(22, Endian.little), 1); // mono
    expect(bd.getUint16(34, Endian.little), 16); // bits
    expect(bd.getUint32(40, Endian.little), pcm.length * 2);
    for (var i = 0; i < pcm.length; i++) {
      expect(bd.getInt16(44 + i * 2, Endian.little), pcm[i]);
    }
  });
}
