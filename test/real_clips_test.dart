// ignore_for_file: avoid_print
// Fait tourner le détecteur sur de vrais extraits (test/fixtures/*.wav,
// hors git). Lancer avec : flutter test test/real_clips_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:bpm_detector_app/bpm_detector.dart';
import 'package:flutter_test/flutter_test.dart';

Int16List readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  // On cherche le bloc "data" (l'en-tête peut varier)
  var off = 12;
  while (off + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(off, off + 4));
    final size = bd.getUint32(off + 4, Endian.little);
    if (id == 'data') {
      final n = size ~/ 2;
      final out = Int16List(n);
      for (var i = 0; i < n; i++) {
        out[i] = bd.getInt16(off + 8 + i * 2, Endian.little);
      }
      return out;
    }
    off += 8 + size;
  }
  throw StateError('pas de bloc data');
}

void main() {
  final dir = Directory('test/fixtures');
  if (!dir.existsSync()) return;
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.wav')).toList()..sort((a, b) => a.path.compareTo(b.path));
  test('clips réels', () {
    for (final f in files) {
      final pcm = readWav(f.path);
      final d = BpmDetector()..debugTrace = true;
      print('=== ${f.path.split('/').last}  (${(pcm.length / 44100).toStringAsFixed(1)} s)');
      const chunk = 4096;
      for (var i = 0; i < pcm.length; i += chunk) {
        d.addSamples(Int16List.sublistView(pcm, i, (i + chunk).clamp(0, pcm.length)));
      }
      final r = d.estimate();
      if (r == null) { print('  → null'); continue; }
      print('  → ${r.bpm.toStringAsFixed(1)}  conf ${r.confidence.toStringAsFixed(2)}  cands ${r.candidates.map((c) => "${c.bpm.toStringAsFixed(0)}(${c.score.toStringAsFixed(2)})").join(" ")}');
    }
  });
}
