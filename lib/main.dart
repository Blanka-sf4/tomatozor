import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'bpm_detector.dart';

// Paramètres audio, partagés avec le détecteur.
const int kSampleRate = 44100; // échantillons par seconde
const int kNumChannels = 1; // mono

/// Logarithme en base 10 (Dart ne fournit que le log népérien).
double log10(double x) => log(x) / ln10;

/// Convertit un paquet d'octets PCM 16 bits little-endian en échantillons.
Int16List pcm16ToSamples(Uint8List bytes) {
  final count = bytes.lengthInBytes ~/ 2;
  final data = ByteData.sublistView(bytes);
  final samples = Int16List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little);
  }
  return samples;
}

/// Une plage de tempo sélectionnable. Une plage 2:1 (ex. 80-160) ne
/// contient qu'une seule octave d'un tempo donné : pas d'ambiguïté.
class TempoRange {
  const TempoRange(this.label, this.min, this.max);
  final String label;
  final double min;
  final double max;
}

const kRanges = [
  TempoRange('Auto', 60, 450),
  TempoRange('60-120', 60, 120),
  TempoRange('80-160', 80, 160),
  TempoRange('100-200', 100, 200),
  TempoRange('150-300', 150, 300),
  TempoRange('225-450', 225, 450),
];

void main() {
  runApp(const BpmApp());
}

class BpmApp extends StatelessWidget {
  const BpmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BPM Detector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const ListenScreen(),
    );
  }
}

class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;

  final BpmDetector _detector = BpmDetector(sampleRate: kSampleRate);

  bool _isListening = false;
  String? _error;

  // Vu-mètre.
  double _level = 0.0;
  double _dbLevel = -60.0;

  // On relance une estimation tous les 0,5 s de son reçu.
  int _samplesSinceEstimate = 0;
  static const int _estimateEvery = kSampleRate ~/ 2;

  // Dernières estimations, pour afficher une médiane stable.
  final List<double> _history = [];
  static const int _historyLength = 7;

  BpmResult? _lastResult;
  double? _displayBpm;
  int _rangeIndex = 0;

  @override
  void dispose() {
    _stop();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Permission micro refusée.');
      return;
    }

    _detector.reset();
    _history.clear();
    _samplesSinceEstimate = 0;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kSampleRate,
        numChannels: kNumChannels,
        // On coupe les traitements "téléphone" d'Android : ils lissent
        // le volume et suppriment le bruit, ce qui écrase justement les
        // attaques qu'on cherche à détecter.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    _subscription = stream.listen(_onAudioChunk);

    // Garde l'écran allumé tant qu'on écoute.
    await WakelockPlus.enable();

    setState(() {
      _isListening = true;
      _error = null;
      _lastResult = null;
      _displayBpm = null;
    });
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
    await WakelockPlus.disable();
    if (mounted) {
      setState(() {
        _isListening = false;
        _level = 0.0;
        _dbLevel = -60.0;
      });
    }
  }

  void _onAudioChunk(Uint8List bytes) {
    final samples = pcm16ToSamples(bytes);
    if (samples.isEmpty) return;

    // 1. Nourrir le détecteur.
    _detector.addSamples(samples);

    // 2. Vu-mètre (RMS → dB).
    double sumSquares = 0;
    for (final s in samples) {
      sumSquares += s * s;
    }
    final rms = sqrt(sumSquares / samples.length);
    final db = 20 * log10(max(rms, 1.0) / 32768.0);
    final level = ((db + 60) / 60).clamp(0.0, 1.0);

    // 3. Estimation périodique.
    _samplesSinceEstimate += samples.length;
    BpmResult? result;
    if (_samplesSinceEstimate >= _estimateEvery) {
      _samplesSinceEstimate = 0;
      result = _detector.estimate();
      if (result != null) {
        // Trace lisible avec `adb logcat -s flutter`, pour le debug.
        final cands = result.candidates
            .map((c) => '${c.bpm.toStringAsFixed(1)}(${c.score.toStringAsFixed(2)})')
            .join(' ');
        debugPrint(
          'BPM ${result.bpm.toStringAsFixed(1)} '
          'conf ${result.confidence.toStringAsFixed(2)} '
          'range ${kRanges[_rangeIndex].label} '
          'cands $cands',
        );
        _history.add(result.bpm);
        if (_history.length > _historyLength) _history.removeAt(0);
      }
    }

    setState(() {
      _dbLevel = db;
      _level = _level * 0.7 + level * 0.3;
      if (result != null) {
        _lastResult = result;
        _displayBpm = _median(_history);
      }
    });
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  void _selectRange(int index) {
    final range = kRanges[index];
    _detector.minBpm = range.min;
    _detector.maxBpm = range.max;
    // L'a priori de tempo ne sert qu'en Auto : dans une plage 2:1 choisie
    // par l'utilisateur, c'est lui qui a tranché.
    _detector.usePrior = index == 0;
    // La plage change le résultat : on repart sur un historique vierge.
    _history.clear();
    setState(() {
      _rangeIndex = index;
      _displayBpm = null;
      _lastResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _lastResult;
    final buffered = _detector.bufferedSeconds;

    return Scaffold(
      appBar: AppBar(title: const Text('BPM Detector')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),

            // --- Le gros chiffre ---------------------------------------
            Text(
              _displayBpm == null ? '—' : _displayBpm!.toStringAsFixed(1),
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 96,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text('BPM', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),

            // --- Confiance / état ----------------------------------------
            SizedBox(
              height: 48,
              child: Column(
                children: [
                  if (!_isListening)
                    Text('Appuie sur le micro', style: theme.textTheme.bodyLarge)
                  else if (result == null)
                    Text(
                      'Analyse… ${buffered.toStringAsFixed(1)} s',
                      style: theme.textTheme.bodyLarge,
                    )
                  else ...[
                    Text(
                      'Confiance : ${(result.confidence * 100).toStringAsFixed(0)} %',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Candidats : ${result.candidates.take(3).map((c) => c.bpm.toStringAsFixed(0)).join('  ·  ')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),

            // --- Le bouton rond, au centre ---------------------------------
            SizedBox(
              width: 120,
              height: 120,
              child: FilledButton(
                onPressed: _isListening ? _stop : _start,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: _isListening
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  size: 56,
                ),
              ),
            ),
            const Spacer(),

            // --- Sélecteur de plage --------------------------------------
            Text('Plage de tempo', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < kRanges.length; i++)
                  ChoiceChip(
                    label: Text(kRanges[i].label),
                    selected: i == _rangeIndex,
                    onSelected: (_) => _selectRange(i),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // --- Vu-mètre ---------------------------------------------------
            Row(
              children: [
                const Icon(Icons.mic, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _level,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_dbLevel.toStringAsFixed(0)} dB',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
