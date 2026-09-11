import 'dart:math';
import 'dart:typed_data';

import 'package:bpm_detector_app/bpm_detector.dart';
import 'package:flutter_test/flutter_test.dart';

const fs = 44100;

/// Fabrique un signal de [seconds] secondes à [bpm] : un kick grave à
/// chaque temps, un "charley" aigu sur les contretemps, du bruit de fond.
/// Si [alternate] est vrai, un temps sur deux est une caisse claire plus
/// faible et plus aiguë (pattern kick-snare classique).
Int16List synth(
  double bpm, {
  double seconds = 10,
  bool alternate = false,
  bool dotted = false,
}) {
  final rng = Random(42);
  final total = (seconds * fs).round();
  final out = Float64List(total);
  final beatLen = 60 / bpm * fs;

  var beat = 0;
  for (var pos = 0.0; pos < total; pos += beatLen, beat++) {
    final snare = alternate && beat.isOdd;
    final freq = snare ? 180.0 : 60.0;
    final amp = snare ? 0.35 : 0.6;
    final start = pos.round();
    for (var i = 0; i < (0.08 * fs).round() && start + i < total; i++) {
      final t = i / fs;
      out[start + i] += amp * sin(2 * pi * freq * t) * exp(-t / 0.02);
    }
    // Basse syncopée à la croche pointée (3/4 de temps) : le piège
    // classique de la house, une périodicité réelle à 4/3 du tempo.
    if (dotted) {
      final d = (pos + beatLen * 0.75).round();
      for (var i = 0; i < (0.06 * fs).round() && d + i < total; i++) {
        final t = i / fs;
        out[d + i] += 0.45 * sin(2 * pi * 80 * t) * exp(-t / 0.03);
      }
    }
    // Charley sur le contretemps : 6 kHz, très court.
    final hh = (pos + beatLen / 2).round();
    for (var i = 0; i < (0.02 * fs).round() && hh + i < total; i++) {
      final t = i / fs;
      out[hh + i] += 0.2 * sin(2 * pi * 6000 * t) * exp(-t / 0.005);
    }
  }

  final pcm = Int16List(total);
  for (var i = 0; i < total; i++) {
    final v = out[i] + (rng.nextDouble() * 2 - 1) * 0.02;
    pcm[i] = (v.clamp(-1.0, 1.0) * 32767).round();
  }
  return pcm;
}

/// Pousse le signal par paquets de 4096, comme le ferait le micro.
BpmResult? run(BpmDetector d, Int16List pcm) {
  const chunk = 4096;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = min(i + chunk, pcm.length);
    d.addSamples(Int16List.sublistView(pcm, i, end));
  }
  return d.estimate();
}

void main() {
  for (final target in [65.0, 90.0, 128.0, 174.0, 200.0, 220.0]) {
    test('détecte $target BPM (plage auto 60-450)', () {
      final d = BpmDetector();
      final res = run(d, synth(target));
      expect(res, isNotNull);
      expect(res!.bpm, closeTo(target, 1.5));
      expect(res.confidence, greaterThan(0.5));
    });
  }

  for (final target in [230.0, 290.0, 350.0, 400.0, 450.0]) {
    test('détecte $target BPM (plage 225-450)', () {
      final d = BpmDetector(minBpm: 225, maxBpm: 450)..usePrior = false;
      final res = run(d, synth(target));
      expect(res, isNotNull);
      expect(res!.bpm, closeTo(target, 1.5));
    });
  }

  test('290 BPM en auto : l\'a priori replie sur 145 (comportement voulu)', () {
    final res = run(BpmDetector(), synth(290));
    expect(res!.bpm, closeTo(145, 1.5));
  });

  test('pattern kick-snare à 120 BPM, plage 100-200 : trouve 120', () {
    final d = BpmDetector(minBpm: 100, maxBpm: 200)..usePrior = false;
    final res = run(d, synth(120, alternate: true));
    expect(res, isNotNull);
    expect(res!.bpm, closeTo(120, 1.5));
  });

  test('pattern kick-snare à 120 BPM, plage 150-300 : trouve 240', () {
    final d = BpmDetector(minBpm: 150, maxBpm: 300)..usePrior = false;
    final res = run(d, synth(120, alternate: true));
    expect(res, isNotNull);
    expect(res!.bpm, closeTo(240, 3));
  });

  test('pattern kick-snare à 120 BPM, plage auto : trouve 120 (pas 60)', () {
    final d = BpmDetector();
    final res = run(d, synth(120, alternate: true));
    expect(res, isNotNull);
    expect(res!.bpm, closeTo(120, 1.5));
  });

  test('basse à la croche pointée à 125 BPM, auto : trouve 125 (pas 167)', () {
    final res = run(BpmDetector(), synth(125, dotted: true));
    expect(res, isNotNull);
    expect(res!.bpm, closeTo(125, 1.5));
  });

  test('phase du beat : le prochain temps prédit tombe sur un kick', () {
    const bpm = 120.0;
    final d = BpmDetector();
    final res = run(d, synth(bpm))!;
    expect(res.periodSeconds, closeTo(0.5, 0.005));
    // Le signal fait 10 s pile, kicks à 0, 0.5, 1.0 … donc le prochain
    // tombe à 10.0 s exactement (ou un multiple de 0.5 après).
    final next = 10.0 + res.secondsToNextBeat;
    final offBeat = (next / 0.5) % 1.0;
    expect(min(offBeat, 1 - offBeat), lessThan(0.06));
  });

  test('pas assez de son → null', () {
    final d = BpmDetector();
    expect(run(d, synth(120, seconds: 2)), isNull);
  });

  test('silence → null', () {
    final d = BpmDetector();
    expect(run(d, Int16List(fs * 5)), isNull);
  });
}
