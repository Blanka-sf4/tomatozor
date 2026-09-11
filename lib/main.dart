import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'bpm_detector.dart';

// Paramètres audio, partagés avec le détecteur.
const int kSampleRate = 44100; // échantillons par seconde
const int kNumChannels = 1; // mono

/// Les couleurs de l'arc-en-ciel, pour le titre et les chiffres calés.
const kRainbow = [
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFE600),
  Color(0xFF34C759),
  Color(0xFF1E90FF),
  Color(0xFF7B4DFF),
  Color(0xFFFF2D9B),
];

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
  runApp(const TomatozorApp());
}

class TomatozorApp extends StatelessWidget {
  const TomatozorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOMATOZOR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF69B4),
          brightness: Brightness.dark,
        ),
      ),
      home: const ListenScreen(),
    );
  }
}

/// Texte peint avec un dégradé arc-en-ciel. [shift] (0..1) fait tourner
/// les couleurs, pour l'animation.
class RainbowText extends StatelessWidget {
  const RainbowText(this.text, {super.key, required this.style, this.shift = 0});
  final String text;
  final TextStyle style;
  final double shift;

  @override
  Widget build(BuildContext context) {
    final n = kRainbow.length;
    final start = (shift * n).floor() % n;
    final colors = [
      for (var i = 0; i <= n; i++) kRainbow[(start + i) % n],
    ];
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        colors: colors,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final AudioPlayer _player = AudioPlayer();

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

  // --- Verrouillage ("le BPM est fixé") ---------------------------------
  // Calé quand les 7 dernières estimations tiennent dans ±1,5 % ; décalé
  // quand elles s'écartent de plus de 4 %. L'écart entre les deux seuils
  // (hystérésis) évite de clignoter autour de la limite.
  bool _locked = false;
  DateTime _lastCelebration = DateTime.fromMillisecondsSinceEpoch(0);
  late final AnimationController _flash;

  // --- Horloge du beat --------------------------------------------------------
  // Le détecteur nous dit quand tombe le prochain temps ; à partir de là on
  // extrapole avec la période. Le ticker met à jour [_pulse] à chaque image.
  late final Ticker _ticker;
  final ValueNotifier<double> _pulse = ValueNotifier(0);
  DateTime? _beatAnchor;
  double _beatPeriodMs = 500;
  // Le son met un peu de temps à arriver du micro jusqu'à nous : on avance
  // l'horloge d'autant. À ajuster à l'oreille si le point est en retard.
  static const int _audioLatencyMs = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _ticker = createTicker(_onTick);
    // Le son d'alerte ne doit pas couper la musique qui joue.
    _player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    _player.setVolume(0.7);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _ticker.dispose();
    _flash.dispose();
    _pulse.dispose();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  /// Appli passée en arrière-plan (bouton Accueil, écran éteint) : on
  /// libère le micro. `inactive` est exclu : c'est l'état pendant la popup
  /// de permission, on ne veut pas couper à ce moment-là.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _isListening) {
      _stop();
    }
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Permission micro refusée.');
      return;
    }

    _detector.reset();
    _history.clear();
    _samplesSinceEstimate = 0;
    _locked = false;
    _beatAnchor = null;

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
    _ticker.start();

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
    _ticker.stop();
    _pulse.value = 0;
    if (mounted) {
      setState(() {
        _isListening = false;
        _locked = false;
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
        _logResult(result);
        _history.add(result.bpm);
        if (_history.length > _historyLength) _history.removeAt(0);
        _updateBeatClock(result);
        _updateLock();
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

  void _logResult(BpmResult result) {
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
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  // --- Beat -----------------------------------------------------------------

  void _updateBeatClock(BpmResult result) {
    final now = DateTime.now();
    _beatPeriodMs = result.periodSeconds * 1000;
    _beatAnchor = now.add(
      Duration(
        milliseconds:
            (result.secondsToNextBeat * 1000).round() - _audioLatencyMs,
      ),
    );
  }

  void _onTick(Duration _) {
    final anchor = _beatAnchor;
    if (anchor == null) return;
    final elapsed =
        DateTime.now().difference(anchor).inMicroseconds / 1000.0;
    // Phase dans le temps courant, 0 = sur le beat, → 1 juste avant le
    // suivant. Le modulo gère aussi le cas "avant l'ancre" (négatif).
    final phase = ((elapsed / _beatPeriodMs) % 1.0 + 1.0) % 1.0;
    // Attaque franche, décroissance rapide : ça "tape".
    _pulse.value = exp(-phase * 6);
  }

  // --- Verrouillage ---------------------------------------------------------

  void _updateLock() {
    if (_history.length < _historyLength) return;
    final med = _median(_history);
    final spread =
        (_history.reduce(max) - _history.reduce(min)) / med;

    if (!_locked && spread < 0.015) {
      _locked = true;
      _celebrate();
    } else if (_locked && spread > 0.04) {
      _locked = false;
    }
  }

  Future<void> _celebrate() async {
    // Pas plus d'une fête toutes les 5 s, sinon ça devient pénible.
    final now = DateTime.now();
    if (now.difference(_lastCelebration).inSeconds < 5) return;
    _lastCelebration = now;

    _flash.forward(from: 0);
    unawaited(_player.play(AssetSource('sounds/sneeze.wav')));
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
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
      _locked = false;
    });
  }

  // --- Interface ---------------------------------------------------------------

  Widget _buildTitle(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall!.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: 3,
      fontStyle: FontStyle.italic,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🦄', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        RainbowText('TOMATOZOR', style: style),
        const SizedBox(width: 10),
        const Text('🦄', style: TextStyle(fontSize: 26)),
      ],
    );
  }

  Widget _buildBpmDigits(BuildContext context) {
    final style = Theme.of(context).textTheme.displayLarge!.copyWith(
      fontSize: 96,
      fontWeight: FontWeight.bold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final text = _displayBpm == null ? '—' : _displayBpm!.toStringAsFixed(1);

    if (!_locked) return Text(text, style: style);

    // Calé : pendant le flash, les couleurs tournent et le texte clignote ;
    // ensuite, arc-en-ciel fixe.
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, _) {
        final t = _flash.value;
        final flashing = _flash.isAnimating;
        final blink = flashing ? (sin(t * 2 * pi * 9) > 0 ? 1.0 : 0.3) : 1.0;
        return Opacity(
          opacity: blink,
          child: RainbowText(text, style: style, shift: flashing ? t * 3 : 0),
        );
      },
    );
  }

  Widget _buildBeatDot() {
    return ValueListenableBuilder<double>(
      valueListenable: _pulse,
      builder: (context, pulse, _) {
        final size = 18 + 26 * pulse;
        return SizedBox(
          height: 48,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  const Color(0xFF7B2C6B),
                  const Color(0xFFFF69B4),
                  pulse,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF69B4).withValues(alpha: 0.6 * pulse),
                    blurRadius: 24 * pulse,
                    spreadRadius: 4 * pulse,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _lastResult;
    final buffered = _detector.bufferedSeconds;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _buildTitle(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),

            // --- Le gros chiffre + le point qui bat ----------------------
            _buildBpmDigits(context),
            Text('BPM', style: theme.textTheme.titleLarge),
            _buildBeatDot(),

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
                      _locked
                          ? 'Calé ✓  ·  confiance ${(result.confidence * 100).toStringAsFixed(0)} %'
                          : 'Confiance : ${(result.confidence * 100).toStringAsFixed(0)} %',
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
