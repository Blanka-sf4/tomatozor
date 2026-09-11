// ignore_for_file: avoid_print
// Banc d'essai sur de vrais extraits : test/fixtures/<style><bpm>_<x>.wav
// (hors git). Le BPM vrai est dans le nom. Lancer :
//   flutter test test/real_clips_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:bpm_detector_app/bpm_detector.dart';
import 'package:flutter_test/flutter_test.dart';

Int16List readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
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

/// Note un résultat : ✓ juste (±3 %), ×2 / ÷2 / ×4 / ×1,5… sinon ✗.
String verdict(double got, double truth) {
  for (final (k, label) in [(1.0, '✓'), (2.0, '×2'), (0.5, '÷2'), (4.0, '×4'), (1.5, '×1,5'), (4 / 3, '×4/3'), (2 / 3, '×2/3'), (3.0, '×3')]) {
    if ((got / (truth * k) - 1).abs() < 0.04) return label;
  }
  return '✗';
}

void main() {
  final dir = Directory('test/fixtures');
  if (!dir.existsSync()) return;
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.wav')).toList()..sort((a, b) => a.path.compareTo(b.path));
  final trace = Platform.environment['TRACE'] == '1';

  test('clips réels', () {
    var ok = 0;
    for (final f in files) {
      final name = f.path.split('/').last.replaceAll('.wav', '');
      final truth = double.parse(RegExp(r'(\d+)').firstMatch(name)!.group(1)!);
      final pcm = readWav(f.path);
      final d = BpmDetector()..debugTrace = trace;
      if (trace) print('=== $name');
      const chunk = 4096;
      for (var i = 0; i < pcm.length; i += chunk) {
        d.addSamples(Int16List.sublistView(pcm, i, (i + chunk).clamp(0, pcm.length)));
      }
      final r = d.estimate();
      if (r == null) { print('  $name → null'); continue; }
      final v = verdict(r.bpm, truth);
      if (v == '✓') ok++;
      print('  ${name.padRight(10)} vrai ${truth.toStringAsFixed(0).padLeft(3)} → ${r.bpm.toStringAsFixed(1).padLeft(6)}  $v   conf ${r.confidence.toStringAsFixed(2)}  cands ${r.candidates.map((c) => "${c.bpm.toStringAsFixed(0)}(${c.score.toStringAsFixed(2)})").join(" ")}');
    }
    print('  ==> $ok / ${files.length} justes');
  });
}
