import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:record/record.dart';
import 'package:vibration/vibration.dart';
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

/// Dégradé "incendie", du bas (jaune) vers le haut (rouge sombre).
const kFire = [
  Color(0xFF7A0000),
  Color(0xFFE62E00),
  Color(0xFFFF8A00),
  Color(0xFFFFE066),
];

/// Fond kawaii du mode normal : pastel arc-en-ciel, du rose au lavande.
const kKawaiiBackground = [
  Color(0xFFFFC1E3),
  Color(0xFFFFD6A5),
  Color(0xFFFFF5BA),
  Color(0xFFC1FFD7),
  Color(0xFFB5DEFF),
  Color(0xFFE0C3FC),
];

/// Fond du mode secours : braises, du noir au orange.
const kFireBackground = [
  Color(0xFF0E0000),
  Color(0xFF3A0600),
  Color(0xFF8A1500),
  Color(0xFFE04A00),
];

const kYellowSign = Color(0xFFFFD600);

const kPurple = Color(0xFF7B2CBF);
const kPink = Color(0xFFFF69B4);
const kAlertRed = Color(0xFFE53935);

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

/// Les deux modes de l'appli.
enum AppMode {
  /// Écoute au micro, détection automatique.
  listen,

  /// "Mode de secours" : tap tempo, on tape le rythme sur le dino.
  tap,
}

void main() {
  runApp(const TomatozorApp());
}

class TomatozorApp extends StatelessWidget {
  const TomatozorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOMATOZOR Pastelle Edition',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPink,
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
  const RainbowText(
    this.text, {
    super.key,
    required this.style,
    this.shift = 0,
  });
  final String text;
  final TextStyle style;
  final double shift;

  @override
  Widget build(BuildContext context) {
    final n = kRainbow.length;
    final start = (shift * n).floor() % n;
    final colors = [for (var i = 0; i <= n; i++) kRainbow[(start + i) % n]];
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

/// Une lettre façon tag : ombre portée, contour épais, remplissage en
/// dégradé vertical ([colors], du haut vers le bas).
class GraffitiLetter extends StatelessWidget {
  const GraffitiLetter(
    this.char, {
    super.key,
    required this.colors,
    this.strokeColor = Colors.black,
    this.shadowColor = const Color(0xFF1E0630),
    this.fontSize = 72,
  });
  final String char;
  final List<Color> colors;
  final Color strokeColor;
  final Color shadowColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Contour et ombre proportionnels à la taille.
    final k = fontSize / 72;
    final style = TextStyle(
      fontFamily: 'RubikSprayPaint',
      fontSize: fontSize,
      height: 1.0,
    );
    return Stack(
      children: [
        Transform.translate(
          offset: Offset(5 * k, 7 * k),
          child: Text(char, style: style.copyWith(color: shadowColor)),
        ),
        Text(
          char,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 9 * k
              ..strokeJoin = StrokeJoin.round
              ..color = strokeColor,
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: colors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect),
          child: Text(char, style: style.copyWith(color: Colors.white)),
        ),
      ],
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
  AppMode _mode = AppMode.listen;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final AudioPlayer _player = AudioPlayer();

  final BpmDetector _detector = BpmDetector(sampleRate: kSampleRate);

  bool _isListening = false;
  // Vrai dès que le micro a capté un vrai signal (> -45 dB) depuis le start.
  bool _soundDetected = false;
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

  // --- Tap tempo (mode de secours) ---------------------------------------
  // Instants des taps. Un silence de plus de 2 s remet à zéro.
  final List<DateTime> _taps = [];
  static const int _tapsNeeded = 8;
  static const Duration _tapTimeout = Duration(seconds: 2);
  // Rebond du dino à chaque tap.
  final ValueNotifier<double> _dinoBounce = ValueNotifier(0);

  // --- Verrouillage ("le BPM est fixé") ---------------------------------
  // Calé quand les 7 dernières estimations (ou 8 taps) tiennent dans
  // ±1,5 % (±3 % pour les taps, on n'est pas des machines). Une fois
  // calé : fête, micro coupé, chiffre figé, licornes en transe. Le bouton
  // relance une recherche.
  bool _locked = false;
  late final AnimationController _flash;

  // --- Horloge du beat --------------------------------------------------------
  // Le détecteur (ou les taps) nous dit quand tombe le prochain temps ; à
  // partir de là on extrapole avec la période. Le ticker met à jour
  // [_pulse] à chaque image, et [_tick] sert aux animations continues.
  late final Ticker _ticker;
  final ValueNotifier<double> _pulse = ValueNotifier(0);
  final ValueNotifier<double> _tick = ValueNotifier(0);
  DateTime? _beatAnchor;
  double _beatPeriodMs = 500;
  // Numéro du temps courant : sa parité fait pencher les licornes d'un côté
  // puis de l'autre.
  int _beatIndex = 0;
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
    // Le ticker tourne en permanence : flammes, bannière néon, rebond du
    // dino, point de beat. Coût négligeable, et ça simplifie la logique.
    _ticker = createTicker(_onTick)..start();
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
    _tick.dispose();
    _dinoBounce.dispose();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  /// Appli passée en arrière-plan (bouton Accueil, écran éteint) : on
  /// libère tout. `inactive` est exclu : c'est l'état pendant la popup
  /// de permission, on ne veut pas couper à ce moment-là.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stop();
    }
  }

  // --- Mode ---------------------------------------------------------------------

  void _switchMode() {
    _stop();
    _taps.clear();
    setState(() {
      _mode = _mode == AppMode.listen ? AppMode.tap : AppMode.listen;
      _displayBpm = null;
      _lastResult = null;
    });
    if (_mode == AppMode.tap) WakelockPlus.enable();
  }

  // --- Écoute (mode normal) ---------------------------------------------------------

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

    setState(() {
      _isListening = true;
      _soundDetected = false;
      _error = null;
      _lastResult = null;
      _displayBpm = null;
    });
  }

  /// Coupe le micro seulement. Le point de beat et les licornes continuent
  /// sur l'horloge interne : on connaît la période et la phase, pas besoin
  /// du son pour extrapoler.
  Future<void> _stopMic() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
        _level = 0.0;
        _dbLevel = -60.0;
      });
    }
  }

  /// Arrêt complet : micro, horloge du beat, écran libre.
  Future<void> _stop() async {
    await _stopMic();
    await WakelockPlus.disable();
    _pulse.value = 0;
    _beatAnchor = null;
    if (mounted) {
      setState(() => _locked = false);
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
        if (_locked) {
          // Un dernier paquet peut arriver pendant la coupure du micro.
          result = null;
        } else {
          _history.add(result.bpm);
          if (_history.length > _historyLength) _history.removeAt(0);
          _updateBeatClock(result.periodSeconds, result.secondsToNextBeat);
          _updateLock();
        }
      }
    }

    setState(() {
      _dbLevel = db;
      _level = _level * 0.7 + level * 0.3;
      if (db > -45) _soundDetected = true;
      if (result != null) {
        _lastResult = result;
        _displayBpm = _median(_history);
      }
    });
  }

  void _logResult(BpmResult result) {
    // Trace lisible avec `adb logcat -s flutter`, pour le debug.
    final cands = result.candidates
        .map(
          (c) => '${c.bpm.toStringAsFixed(1)}(${c.score.toStringAsFixed(2)})',
        )
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

  void _updateLock() {
    if (_history.length < _historyLength) return;
    final med = _median(_history);
    final spread = (_history.reduce(max) - _history.reduce(min)) / med;

    if (spread < 0.015) {
      _locked = true;
      _celebrate();
      // Fixé : plus besoin d'écouter. Le bouton repasse en violet ; appuyer
      // dessus relance une recherche.
      _stopMic();
    }
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
    if (_locked) _stop();
    setState(() {
      _rangeIndex = index;
      _displayBpm = null;
      _lastResult = null;
      _locked = false;
    });
  }

  // --- Tap tempo (mode de secours) -----------------------------------------------

  void _onTap() {
    final now = DateTime.now();
    _dinoBounce.value = 1;

    if (_locked) {
      // Calé : un tap relance une nouvelle mesure.
      _taps.clear();
      _locked = false;
      _beatAnchor = null;
    } else if (_taps.isNotEmpty && now.difference(_taps.last) > _tapTimeout) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > _tapsNeeded + 1) _taps.removeAt(0);

    double? bpm;
    if (_taps.length >= 2) {
      final intervals = <double>[];
      for (var i = 1; i < _taps.length; i++) {
        intervals.add(
          _taps[i].difference(_taps[i - 1]).inMicroseconds / 1000.0,
        );
      }
      final meanMs = intervals.reduce((a, b) => a + b) / intervals.length;
      bpm = 60000 / meanMs;

      // Horloge du beat : le prochain temps est un intervalle après ce tap.
      _beatPeriodMs = meanMs;
      _beatAnchor = now;

      // Calé quand on a assez de taps et qu'ils sont réguliers.
      if (intervals.length >= _tapsNeeded - 1) {
        final spread = (intervals.reduce(max) - intervals.reduce(min)) / meanMs;
        // Un humain tape à ±5 % près : on tolère 12 % entre le plus court
        // et le plus long intervalle.
        if (spread < 0.12) {
          _locked = true;
          _celebrate();
        }
      }
    }

    setState(() => _displayBpm = bpm);
  }

  // --- Beat -----------------------------------------------------------------

  void _updateBeatClock(double periodSeconds, double secondsToNextBeat) {
    final now = DateTime.now();
    _beatPeriodMs = periodSeconds * 1000;
    _beatAnchor = now.add(
      Duration(
        milliseconds: (secondsToNextBeat * 1000).round() - _audioLatencyMs,
      ),
    );
  }

  void _onTick(Duration elapsed) {
    _tick.value = elapsed.inMicroseconds / 1e6;
    // Le rebond du dino retombe tout seul.
    if (_dinoBounce.value > 0) {
      _dinoBounce.value = max(0, _dinoBounce.value - 0.08);
    }

    final anchor = _beatAnchor;
    if (anchor == null) return;
    final ms = DateTime.now().difference(anchor).inMicroseconds / 1000.0;
    // Phase dans le temps courant, 0 = sur le beat, → 1 juste avant le
    // suivant. Le modulo gère aussi le cas "avant l'ancre" (négatif).
    final phase = ((ms / _beatPeriodMs) % 1.0 + 1.0) % 1.0;
    _beatIndex = (ms / _beatPeriodMs).floor();
    // Attaque franche, décroissance rapide : ça "tape".
    _pulse.value = exp(-phase * 6);
  }

  Future<void> _celebrate() async {
    _flash.forward(from: 0);
    // Cheval en mode normal, cochon en mode secours.
    final sound = _mode == AppMode.tap
        ? 'sounds/oink.wav'
        : 'sounds/sneeze.wav';
    unawaited(_player.play(AssetSource(sound)));
    // Deux secousses. Le paquet `vibration` pilote le moteur directement,
    // indépendamment du réglage "vibration au toucher" du téléphone.
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(pattern: [0, 180, 120, 180]);
    }
  }

  // --- Interface ---------------------------------------------------------------

  /// Une licorne. Sage au repos ; calée, elle saute et se penche à chaque
  /// temps, d'un côté puis de l'autre. [flip] la retourne (elles se font
  /// face) et inverse le sens de la danse (elles dansent en miroir).
  Widget _buildUnicorn({required bool flip}) {
    return ValueListenableBuilder<double>(
      valueListenable: _pulse,
      builder: (context, pulse, _) {
        final dancing = _locked;
        final side = (_beatIndex.isEven ? 1 : -1) * (flip ? -1 : 1);
        final angle = dancing ? side * 0.4 * pulse : 0.0;
        final scale = dancing ? 1 + 0.35 * pulse : 1.0;
        final lift = dancing ? -16 * pulse : 0.0;
        Widget u = const Text('🦄', style: TextStyle(fontSize: 60));
        if (flip) u = Transform.flip(flipX: true, child: u);
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(scale: scale, child: u),
          ),
        );
      },
    );
  }

  /// Une flamme qui vacille en permanence (deux sinus décalés, pour que ça
  /// n'ait pas l'air mécanique) et qui grossit sur le beat.
  Widget _buildFlame({required int seed}) {
    return ValueListenableBuilder<double>(
      valueListenable: _tick,
      builder: (context, t, _) {
        final flicker =
            0.10 * sin(t * 11 + seed) + 0.07 * sin(t * 27 + seed * 2.3);
        final beat = _beatAnchor == null ? 0.0 : _pulse.value;
        final scale = 1 + flicker + 0.4 * beat;
        final angle = 0.12 * sin(t * 9 + seed * 1.7);
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: const Text('🔥', style: TextStyle(fontSize: 60)),
          ),
        );
      },
    );
  }

  /// TOMATOZOR façon tag : lettres penchées, contour, une couleur de
  /// l'arc-en-ciel chacune (ou feu en mode secours), et la tête du dino
  /// dans les O.
  Widget _buildHeader(BuildContext context) {
    const word = 'TOMATOZOR';
    const tilts = [-8.0, 6.0, -5.0, 7.0, -6.0, 5.0, -7.0, 6.0, -4.0];
    const lifts = [0.0, -6.0, 4.0, -5.0, 5.0, -3.0, 3.0, -6.0, 2.0];
    final fire = _mode == AppMode.tap;

    final letters = <Widget>[];
    var colorIndex = 0;
    for (var i = 0; i < word.length; i++) {
      final ch = word[i];
      Widget glyph;
      if (ch == 'O') {
        glyph = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Image.asset(
            'assets/images/dino_head.png',
            height: 78,
            filterQuality: FilterQuality.medium,
          ),
        );
      } else if (fire) {
        glyph = GraffitiLetter(
          ch,
          colors: kFire,
          strokeColor: const Color(0xFF3A0000),
          shadowColor: const Color(0xFF2A0A00),
        );
      } else {
        final c = kRainbow[colorIndex++ % kRainbow.length];
        glyph = GraffitiLetter(
          ch,
          colors: [Color.lerp(c, Colors.white, 0.45)!, c],
        );
      }
      letters.add(
        Transform.translate(
          offset: Offset(0, lifts[i]),
          child: Transform.rotate(angle: tilts[i] * pi / 180, child: glyph),
        ),
      );
    }

    // FittedBox étire le mot à toute la largeur disponible.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: FittedBox(
            fit: BoxFit.contain,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: letters,
            ),
          ),
        ),
        // "PASTELLE EDITION" en petit sous le nom, même police, même style.
        _buildSubtitle('PASTELLE EDITION', fire: fire),
        if (fire) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '⚠  MODE DE SECOURS  ⚠',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: kAlertRed,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ),
          _buildSubtitle('PARO EDITION', fire: true, fontSize: 20),
        ],
      ],
    );
  }

  /// Une ligne de sous-titre en petites lettres graffiti.
  Widget _buildSubtitle(
    String text, {
    required bool fire,
    double fontSize = 30,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ch in text.split(''))
              if (ch == ' ')
                SizedBox(width: fontSize * 0.4)
              else
                GraffitiLetter(
                  ch,
                  fontSize: fontSize,
                  colors: fire ? kFire : const [Color(0xFFFFF0F8), kPink],
                  strokeColor: fire ? const Color(0xFF3A0000) : Colors.black,
                  shadowColor: fire
                      ? const Color(0xFF2A0A00)
                      : const Color(0xFF1E0630),
                ),
          ],
        ),
      ),
    );
  }

  /// La bannière néon du bas. Elle "respire" doucement, et flashe sur le
  /// beat quand il y en a un.
  Widget _buildNeonBanner() {
    return ValueListenableBuilder<double>(
      valueListenable: _tick,
      builder: (context, t, _) {
        final breath = 0.5 + 0.5 * sin(t * 2.2);
        final beat = _beatAnchor == null ? 0.0 : _pulse.value;
        final glow = 0.55 + 0.25 * breath + 0.4 * beat;
        final fire = _mode == AppMode.tap;
        // Sur les braises : jaune pâle à halo rose. Sur le pastel : rose
        // vif à halo blanc/jaune, sinon ça se noie dans le fond.
        final color = fire ? const Color(0xFFFFF7B0) : const Color(0xFFE6007E);
        final halo = fire ? kPink : Colors.white;
        final halo2 = fire ? const Color(0xFFFF6A00) : const Color(0xFFFFE600);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'FAIT PÉTER LES GROS SONS !!!',
            style: TextStyle(
              fontFamily: 'RubikSprayPaint',
              fontSize: 40,
              height: 1.0,
              color: color,
              shadows: [
                Shadow(color: halo.withValues(alpha: glow), blurRadius: 8),
                Shadow(color: halo.withValues(alpha: glow), blurRadius: 20),
                Shadow(
                  color: halo2.withValues(alpha: glow * 0.8),
                  blurRadius: 40,
                ),
              ],
            ),
          ),
        );
      },
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
        final color = _mode == AppMode.tap ? const Color(0xFFFF6A00) : kPink;
        return SizedBox(
          height: 48,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(const Color(0xFF7B2C6B), color, pulse),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6 * pulse),
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

  /// Le bouton : la tête du dino, qui rebondit au tap. Son halo dit
  /// l'état : violet au repos, rose quand le micro écoute, orange en mode
  /// secours.
  Widget _buildDinoButton() {
    final tap = _mode == AppMode.tap;
    final active = tap || _isListening;
    final Color glow;
    if (tap) {
      glow = const Color(0xFFFF6A00);
    } else if (_isListening) {
      glow = kPink;
    } else {
      glow = kPurple;
    }
    final VoidCallback onTap;
    if (tap) {
      onTap = _onTap;
    } else {
      onTap = () {
        _dinoBounce.value = 1;
        _isListening ? _stop() : _start();
      };
    }

    return GestureDetector(
      onTapDown: (_) => onTap(),
      child: ValueListenableBuilder<double>(
        valueListenable: _dinoBounce,
        builder: (context, bounce, child) {
          return Transform.scale(scale: 1 - 0.15 * bounce, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: active ? 0.6 : 0.45),
                blurRadius: active ? 36 : 24,
                spreadRadius: active ? 4 : 1,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/dino_head.png',
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final theme = Theme.of(context);
    final result = _lastResult;
    final buffered = _detector.bufferedSeconds;

    final List<Widget> lines;
    if (_mode == AppMode.tap) {
      if (_locked) {
        lines = [
          Text('Calé ✓', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            'Tape le dino pour recommencer',
            style: theme.textTheme.bodySmall,
          ),
        ];
      } else if (_taps.isEmpty) {
        lines = [
          Text(
            'Tape le dino en rythme régulier',
            style: theme.textTheme.bodyLarge,
          ),
        ];
      } else {
        lines = [Text('Continue, régulier…', style: theme.textTheme.bodyLarge)];
      }
    } else if (_locked) {
      lines = [
        Text('Calé ✓', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text('Tape le dino pour recommencer', style: theme.textTheme.bodySmall),
      ];
    } else if (!_isListening) {
      lines = [
        Text(
          'Appuie sur le dino quand le son a pété',
          style: theme.textTheme.bodyLarge,
        ),
      ];
    } else if (!_soundDetected) {
      lines = [
        Text('Micro ouvert, j\'écoute…', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          'Aucun son pour l\'instant (${_dbLevel.toStringAsFixed(0)} dB)',
          style: theme.textTheme.bodySmall,
        ),
      ];
    } else if (result == null) {
      lines = [
        Text('Son détecté ✓', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          'Analyse… ${buffered.toStringAsFixed(1)} s',
          style: theme.textTheme.bodySmall,
        ),
      ];
    } else {
      lines = [
        Text(
          'Confiance : ${(result.confidence * 100).toStringAsFixed(0)} %',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Candidats : ${result.candidates.take(3).map((c) => c.bpm.toStringAsFixed(0)).join('  ·  ')}',
          style: theme.textTheme.bodySmall,
        ),
      ];
    }
    return SizedBox(height: 48, child: Column(children: lines));
  }

  /// Le panneau jaune OPTION, en bas à gauche, en face du ⚠ rouge.
  Widget _buildOptionsSign() {
    return GestureDetector(
      onTap: _showOptions,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: kYellowSign,
          border: Border.all(color: Colors.black, width: 3),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'OPTION',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              kRanges[_rangeIndex].label,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Popup à bordure arc-en-ciel : une case par plage, une seule cochée.
  Future<void> _showOptions() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: kPink,
              brightness: Brightness.dark,
            ),
          ),
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              // La bordure arc-en-ciel : un dégradé en fond, et la boîte
              // sombre par-dessus avec 4 px de marge.
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: kRainbow,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0A24),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RainbowText(
                          'Plage de tempo',
                          style: Theme.of(context).textTheme.titleLarge!
                              .copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < kRanges.length; i++)
                          CheckboxListTile(
                            value: i == _rangeIndex,
                            activeColor: kRainbow[i % kRainbow.length],
                            title: Text(
                              kRanges[i].label,
                              style: TextStyle(
                                fontWeight: i == _rangeIndex
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: i == 0
                                ? const Text('Détection large, a priori 90-180')
                                : null,
                            dense: true,
                            onChanged: (_) {
                              _selectRange(i);
                              setDialogState(() {});
                            },
                          ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Le petit bouton en bas à droite : ⚠ rouge pour passer en mode secours,
  /// micro pour en revenir.
  Widget _buildModeToggle() {
    final tap = _mode == AppMode.tap;
    return IconButton(
      onPressed: _switchMode,
      tooltip: tap ? 'Retour au mode micro' : 'Mode de secours (tap tempo)',
      iconSize: 28,
      color: tap ? kPink : kAlertRed,
      icon: Icon(tap ? Icons.mic : Icons.warning_rounded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tap = _mode == AppMode.tap;

    // Mode normal : fond pastel, donc texte foncé (thème clair).
    // Mode secours : braises, texte clair (thème sombre).
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: tap ? const Color(0xFFFF6A00) : kPink,
        brightness: tap ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    // Le Builder donne un contexte situé SOUS le Theme : sans lui,
    // Theme.of(context) dans les méthodes _build* verrait l'ancien thème.
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: tap ? kFireBackground : kKawaiiBackground,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        _buildHeader(context),
                        const Spacer(),

                        // --- Le gros chiffre, encadré par les licornes / flammes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (tap)
                              _buildFlame(seed: 1)
                            else
                              _buildUnicorn(flip: false),
                            const SizedBox(width: 8),
                            _buildBpmDigits(context),
                            const SizedBox(width: 8),
                            if (tap)
                              _buildFlame(seed: 2)
                            else
                              _buildUnicorn(flip: true),
                          ],
                        ),
                        Text('BPM', style: theme.textTheme.titleLarge),
                        _buildBeatDot(),
                        _buildStatus(context),
                        const Spacer(),

                        // --- Le bouton, au centre ------------------------------
                        _buildDinoButton(),
                        const Spacer(),

                        // --- Bas de l'écran ---------------------------------------
                        const SizedBox(height: 56),
                        _buildNeonBanner(),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!tap)
                    Positioned(left: 8, bottom: 72, child: _buildOptionsSign()),
                  Positioned(right: 4, bottom: 72, child: _buildModeToggle()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
