import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'bpm_detector.dart';
import 'dino.dart';
import 'history.dart';
import 'metronome.dart';
import 'tutorial.dart';

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

/// Lien de téléchargement de l'appli, inclus dans le texte de partage.
/// À REMPLIR quand l'APK sera hébergé (GitHub Releases, Drive…).
const kDownloadUrl = 'https://github.com/Blanka-sf4/tomatozor/releases/latest';

const kYellowSign = Color(0xFFFFD600);
const kGreenSign = Color(0xFF2ECC40);

/// Le cri de la fête dépend du tempo trouvé. Le mode secours garde son
/// cochon, signature du mode.
class Animal {
  const Animal(this.emoji, this.sound, this.ms);
  final String emoji;
  final String sound;

  /// Durée du cri, pour que le dino hurle exactement pendant ce temps.
  final int ms;
}

const kPig = Animal('🐷', 'sounds/oink.wav', 1660);

Animal animalFor(double bpm) {
  if (bpm < 100) return const Animal('🦕', 'sounds/burp.wav', 1700);
  if (bpm < 160) return const Animal('🐴', 'sounds/sneeze.wav', 1850);
  if (bpm < 220) return const Animal('🦖', 'sounds/roar.wav', 1900);
  return const Animal('🐐', 'sounds/goat.wav', 1600);
}

/// Formate un BPM à la française : 172,2.
String fmtBpm(double bpm) => bpm.toStringAsFixed(1).replaceAll('.', ',');

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

/// Le preset caché, débloqué par le Konami des plages (Auto, 60-120, Auto,
/// 60-120). Le détecteur plafonne en pratique vers 15-5000 BPM.
const kCrazyRange = TempoRange('1-9999 🍄', 1, 9999);

/// Une flamme crachée : position de départ, direction, instant de naissance.
class _Flame {
  _Flame(this.born, this.angle, this.speed, this.size, this.spin);
  final double born;
  final double angle;
  final double speed;
  final double size;
  final double spin;
}

/// Les néons de la fête : des traits, cercles et éclairs lumineux de
/// toutes les couleurs, qui clignotent et tournent, plus une bordure qui
/// pulse. [t] : progression 0 → 1 du flash.
class _PartyPainter extends CustomPainter {
  _PartyPainter(this.t, this.seed, {this.count = 42});
  final double t;
  final int seed;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    // Monte en 0,3 s, puis reste. [t] est en secondes depuis le calage.
    final fade = (t / 0.3).clamp(0.0, 1.0);

    // Bordure néon qui pulse
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..shader = SweepGradient(
        colors: [...kRainbow, kRainbow.first],
        transform: GradientRotation(t * 2.5),
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(28)),
      border..color = Colors.white.withValues(alpha: fade),
    );

    // Néons : 42 formes, chacune avec sa couleur, sa vitesse de
    // clignotement et sa rotation.
    for (var i = 0; i < count; i++) {
      final color = kRainbow[i % kRainbow.length];
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final len = 30 + rng.nextDouble() * 90;
      final angle = rng.nextDouble() * 6.28 + t * (rng.nextBool() ? 0.8 : -0.8);
      final blinkRate = 2 + rng.nextDouble() * 4;
      final phase = rng.nextDouble() * 6.28;
      final on = (sin(t * blinkRate * 6.28 + phase) + 1) / 2;
      final alpha = (0.25 + 0.75 * on) * fade;
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final kind = i % 3;
      if (kind == 0) {
        final dx = cos(angle) * len / 2, dy = sin(angle) * len / 2;
        canvas.drawLine(Offset(x - dx, y - dy), Offset(x + dx, y + dy), paint);
      } else if (kind == 1) {
        canvas.drawCircle(
          Offset(x, y),
          len / 4,
          paint..style = PaintingStyle.stroke,
        );
      } else {
        // Éclair : zigzag de 4 segments
        final path = Path()..moveTo(x, y);
        var px = x, py = y;
        for (var k = 0; k < 4; k++) {
          px += cos(angle + (k.isEven ? 0.6 : -0.6)) * len / 4;
          py += sin(angle + (k.isEven ? 0.6 : -0.6)) * len / 4;
          path.lineTo(px, py);
        }
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_PartyPainter old) =>
      old.t != t || old.seed != seed || old.count != count;
}

/// Tranche de tempo du métronome : 0 lent, 1 moyen, 2 rapide, 3 extrême.
int tierFor(double bpm) =>
    bpm < 100 ? 0 : (bpm < 160 ? 1 : (bpm < 220 ? 2 : 3));

/// Les quatre atmosphères du métronome, une par tranche.
/// Fond du métronome : violet psychédélique, champignons.
const kMetroBackground = [
  Color(0xFF12002A),
  Color(0xFF3B0A6B),
  Color(0xFF7A1FB8),
  Color(0xFF3B0A6B),
  Color(0xFF12002A),
];

const kMetroAccents = [
  Color(0xFF6FA8FF),
  kPink,
  Color(0xFFFF8A00),
  Color(0xFFFF00C8),
];

/// Les deux modes de l'appli.
enum AppMode {
  /// Écoute au micro, détection automatique.
  listen,

  /// "Mode de secours" : tap tempo, on tape le rythme sur le dino.
  tap,

  /// Métronome : clics bois, tous les animaux font la fête.
  metro,
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  AppMode _mode = AppMode.listen;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final AudioPlayer _player = AudioPlayer();

  final BpmDetector _detector = BpmDetector(sampleRate: kSampleRate);

  bool _isListening = false;
  // Vrai dès que le micro a capté un vrai signal (> -45 dB) depuis le start.
  bool _soundDetected = false;

  // --- Silence ----------------------------------------------------------------
  // Échantillons consécutifs sous le seuil de "son détecté" (−45 dB).
  // 3 s après du son → "la musique s'est arrêtée", mémoire vidée, on
  // continue d'écouter. 20 s sans jamais rien → micro coupé.
  int _silentSamples = 0;
  static const int _musicStoppedAfter = kSampleRate * 3;
  static const int _nothingHeardAfter = kSampleRate * 20;
  bool _musicStopped = false;
  bool _nothingHeard = false;

  // --- Saturation ------------------------------------------------------------
  // On compte les échantillons en butée (|s| ≥ 32700) sur chaque fenêtre
  // d'estimation (0,5 s). Plus de 1 % = le micro sature : le son est
  // écrasé, les attaques disparaissent, le calage serait faux → bloqué.
  int _clippedInWindow = 0;
  int _samplesInWindow = 0;
  bool _saturated = false;
  DateTime _lastYark = DateTime.fromMillisecondsSinceEpoch(0);

  // --- Tête du dino -------------------------------------------------------------
  // normal | yark (saturation) | squish1..3 (écrasé pendant un tap)
  // _dinoFace = tête imposée (yark, squish*, yell, tongue). 'head' = pas
  // d'imposition : la tête est déduite de la situation (voir _currentFace).
  String _dinoFace = 'head';
  bool _dinoPressed = false;
  final Random _rng = Random();
  // Tête temporaire (hurlement de fête, langue tirée) : on retient celle
  // d'avant pour la remettre ensuite.
  Timer? _faceTimer;
  String? _faceBefore;
  // --- Métronome ---------------------------------------------------------------
  late final Metronome _metro = Metronome(onBeat: _onMetroBeat);
  final List<DateTime> _metroTaps = [];

  // --- Mascottes (chat en mode normal, incognito en mode secours) ----------
  // Frame imposée (miaou, gloups/caché) ou null = vie normale (clignement,
  // oreille, coup d'œil, programmés au hasard dans le ticker).
  final ValueNotifier<String> _mascotFrame = ValueNotifier('cat_normal');
  String? _mascotOverride;
  Timer? _mascotTimer;
  double _nextMascotEventAt = 1.5;
  double _mascotEventUntil = 0.0;

  // Écrasement de la mascotte quand on appuie dessus (1 = écrasée), et
  // son bruit rigolo (pool à faible latence).
  final ValueNotifier<double> _mascotSquish = ValueNotifier(0);
  final Map<String, AudioPool> _squishPools = {};
  // Écrasement de chaque personnage de la parade, par index.
  final Map<int, ValueNotifier<double>> _paradeSquish = {};

  // --- Easter eggs -----------------------------------------------------------
  StreamSubscription<AccelerometerEvent>? _accel;
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _panicTimer;
  // Mode nuit : après 2 min sans rien, tout le monde dort.
  DateTime _lastInteraction = DateTime.now();
  bool _asleep = false;
  // Ronron du chat (appui long) : lecteur en boucle + vibration continue.
  final AudioPlayer _purrPlayer = AudioPlayer();
  Timer? _mascotHoldTimer;
  bool _purring = false;
  // L'œuf du poulet : position 0 → 1 (haut → bas), null = pas d'œuf.
  final ValueNotifier<double?> _egg = ValueNotifier(null);
  bool _eggBroken = false;
  // Délire de Psyllo : fin en secondes-ticker, null = inactif.
  double? _trippyUntil;
  // Le 420 : taps rapides sur le chiffre.
  final List<DateTime> _digitTaps = [];
  bool _show420 = false;
  // Konami des plages : les 4 derniers presets choisis.
  final List<int> _rangeSequence = [];

  // Clignement des yeux : instants du prochain et de la fin du courant.
  final ValueNotifier<bool> _blink = ValueNotifier(false);
  double _nextBlinkAt = 2.0;
  double _blinkUntil = 0.0;
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

  // --- Historique des calages (persistant) ---------------------------------
  final HistoryStore _store = HistoryStore();
  // Les 8 dernières secondes de son, en anneau : c'est l'extrait qu'on
  // fige au calage (exactement ce que le détecteur a analysé).
  static const int _clipSamples = kSampleRate * 8;
  final Int16List _clipRing = Int16List(_clipSamples);
  int _clipWrite = 0;
  int _clipFilled = 0;
  // Lecteur dédié à la réécoute des extraits.
  final AudioPlayer _clipPlayer = AudioPlayer();
  String? _playingFile;

  BpmResult? _lastResult;
  double? _displayBpm;
  int _rangeIndex = 0;

  // --- Tap tempo (mode de secours) ---------------------------------------
  // Instants des taps. Un silence de plus de 2 s remet à zéro.
  final List<DateTime> _taps = [];
  static const int _tapsNeeded = 8;
  static const Duration _tapTimeout = Duration(seconds: 2);
  // Rebond du dino à chaque tap, et chrono de l'appui long (easter egg).
  final ValueNotifier<double> _dinoBounce = ValueNotifier(0);
  Timer? _longPressTimer;
  // Instant du calage au tap : pendant 3 s, impossible de relancer.
  DateTime? _tapLockedAt;
  static const Duration _tapLockHold = Duration(seconds: 3);

  /// Vrai quand les 3 s sont passées : on peut relancer.
  bool get _tapUnlocked =>
      _tapLockedAt != null &&
      DateTime.now().difference(_tapLockedAt!) >= _tapLockHold;

  // Flammes crachées par le dino (mode secours, calé) : des particules
  // nées à sa bouche, qui partent vers l'avant en grossissant.
  final List<_Flame> _flames = [];
  double _nextFlameAt = 0;

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
  // l'horloge d'autant. Réglable dans Options (persisté dans le store).

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
    _clipPlayer.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    _clipPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingFile = null);
    });
    _store.load().then((_) {
      _metro.setBpm(_store.metroBpm);
      _metro.setSound(_store.metroSound);
      _metro.beatsPerBar = _store.metroBeatsPerBar;
      if (mounted) setState(() {});
    });
    // Secousse : magnitude de l'accélération bien au-dessus de la gravité.
    _accel = accelerometerEventStream().listen((e) {
      final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (g > 24 && DateTime.now().difference(_lastShake).inSeconds >= 3) {
        _lastShake = DateTime.now();
        _panic();
      }
    });
    _purrPlayer.setReleaseMode(ReleaseMode.loop);
    _purrPlayer.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    // Un bruit d'écrasement par personnage.
    for (final name in [
      'cat',
      'incog',
      'chicken',
      'dino',
      'goat',
      'pig',
      'unicorn',
      'psyllo',
    ]) {
      AudioPool.create(
        source: AssetSource('sounds/squish_$name.wav'),
        maxPlayers: 2,
        audioContext: AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      ).then((pool) => _squishPools[name] = pool);
    }
    // Le chat t'accueille au lancement — sauf au tout premier, où c'est
    // le tutoriel qui accueille (le chat miaulera après).
    Future.delayed(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      if (!_store.tutorialSeen) {
        await _showTutorial();
        await _store.setTutorialSeen();
      }
      if (mounted) _greet();
    });
  }

  // --- Easter eggs ---------------------------------------------------------------

  /// Secousse : tout le monde panique 2 s — écrasements en rafale et
  /// bruits en cascade.
  void _panic() {
    _wake();
    _panicTimer?.cancel();
    var n = 0;
    const names = [
      'cat',
      'incog',
      'chicken',
      'dino',
      'goat',
      'pig',
      'unicorn',
      'psyllo',
    ];
    _panicTimer = Timer.periodic(const Duration(milliseconds: 130), (timer) {
      _mascotSquish.value = 1;
      _dinoBounce.value = 1;
      for (final sq in _paradeSquish.values) {
        if (_rng.nextBool()) sq.value = 1;
      }
      if (_store.soundsOn) {
        _squishPools[names[_rng.nextInt(names.length)]]?.start();
      }
      if (++n >= 15) timer.cancel();
    });
    _vibrate(pattern: [0, 60, 40, 60, 40, 60]);
  }

  /// Réveil du mode nuit (n'importe quel tap).
  void _wake() {
    _lastInteraction = DateTime.now();
    if (!_asleep) return;
    _asleep = false;
    _playSound('sounds/startle.wav');
    _mascotSquish.value = 1;
    if (mounted) setState(() {});
  }

  /// Appui long sur la mascotte : ronron (chat), moustache (incognito),
  /// œuf (poulet).
  void _mascotHold() {
    switch (_mode) {
      case AppMode.listen:
        _purring = true;
        if (_store.soundsOn) {
          unawaited(_purrPlayer.play(AssetSource('sounds/purr.wav')));
        }
        if (_store.vibrationOn) {
          Vibration.vibrate(pattern: [0, 70, 50], repeat: 0);
        }
      case AppMode.tap:
        _setMascot('incog_mustache', const Duration(milliseconds: 1400));
        _playSound('sounds/gloups.wav');
      case AppMode.metro:
        if (_egg.value == null) {
          _egg.value = 0;
          _eggBroken = false;
          _setMascot('chicken_cluck', const Duration(milliseconds: 500));
        }
    }
  }

  void _mascotRelease() {
    _mascotHoldTimer?.cancel();
    if (_purring) {
      _purring = false;
      unawaited(_purrPlayer.stop());
      Vibration.cancel();
    }
  }

  /// Tap sur le chiffre : 10 en moins de 4 s → 420.
  void _digitTap() {
    final now = DateTime.now();
    _digitTaps.add(now);
    _digitTaps.removeWhere((d) => now.difference(d).inSeconds >= 4);
    if (_digitTaps.length >= 10) {
      _digitTaps.clear();
      setState(() => _show420 = true);
      _playSound('sounds/giggle.wav');
      Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _show420 = false);
      });
    }
  }

  /// Konami des plages : Auto, 60-120, Auto, 60-120 → preset caché.
  void _rangeKonami(int index) {
    _rangeSequence.add(index);
    if (_rangeSequence.length > 4) _rangeSequence.removeAt(0);
    if (!_store.crazyUnlocked &&
        _rangeSequence.length == 4 &&
        _rangeSequence[0] == 0 &&
        _rangeSequence[1] == 1 &&
        _rangeSequence[2] == 0 &&
        _rangeSequence[3] == 1) {
      _store.setCrazyUnlocked();
      _playSound('sounds/giggle.wav');
      _vibrate(pattern: [0, 40, 40, 40, 40, 120]);
    }
  }

  /// Les plages disponibles (avec le preset caché si débloqué).
  List<TempoRange> get _ranges =>
      _store.crazyUnlocked ? [...kRanges, kCrazyRange] : kRanges;

  /// Le tutoriel : 4 écrans, au premier lancement ou depuis Options.
  Future<void> _showTutorial() {
    const kawaii = kKawaiiBackground;
    final pages = [
      const TutorialPage(
        image: 'assets/images/dino_head.png',
        title: 'Tape le dino quand le son a pété',
        body:
            'Le dino écoute la musique au micro et trouve son tempo.\n'
            'Laisse-le bosser 5 à 10 secondes, le point rose bat sur les temps.',
        background: [Color(0xFF7B2C6B), Color(0xFFB03A8C), Color(0xFF3A0F3F)],
        sound: 'sounds/meow.wav',
      ),
      const TutorialPage(
        image: 'assets/images/dino_yell.png',
        title: 'Il se cale, il fait la fête',
        body:
            'Une fois sûr de lui, il crie — un animal différent selon le tempo —\n'
            'et garde 8 secondes de son dans HISTO, avec le BPM.\n'
            'Rap ou trap ? OPTION → 60-120.',
        background: kawaii,
        sound: 'sounds/sneeze.wav',
        titleColors: [Color(0xFFE6007E), Color(0xFF7B2CBF)],
      ),
      const TutorialPage(
        image: 'assets/images/incog_normal.png',
        title: '⚠ Mode de secours',
        body:
            'Trop de bruit, son pourri ? Le bouton rouge en bas.\n'
            'Tape le rythme toi-même sur le dino : il crache des flammes\n'
            'quand il a compris.',
        background: kFireBackground,
        sound: 'sounds/gloups.wav',
        titleColors: kFire,
      ),
      const TutorialPage(
        image: 'assets/images/chicken_normal.png',
        title: '🐔 Métronome',
        body:
            'Le bouton bleu en bas. Règle le tempo, ou reprends-le dans HISTO.\n'
            'Tape un animal : c\'est lui qui fait le clic.',
        background: kMetroBackground,
        sound: 'sounds/cluck.wav',
      ),
    ];
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TutorialScreen(
          pages: pages,
          rainbow: kRainbow,
          onSound: _playSound,
        ),
      ),
    );
  }

  /// Joue un son d'ambiance (cri, squish, accueil…) si les sons sont
  /// activés. Les clics du métronome et la réécoute d'HISTO ne passent pas
  /// par ici : ce sont des fonctions, pas de l'ambiance.
  void _playSound(String asset) {
    if (!_store.soundsOn) return;
    unawaited(_player.play(AssetSource(asset)));
  }

  Future<void> _vibrate({int? duration, List<int>? pattern}) async {
    if (!_store.vibrationOn) return;
    if (!await Vibration.hasVibrator()) return;
    if (pattern != null) {
      await Vibration.vibrate(pattern: pattern);
    } else {
      await Vibration.vibrate(duration: duration ?? 50);
    }
  }

  /// La mascotte du mode courant te salue : le chat miaule, l'incognito
  /// fait gloups et se planque sous son chapeau.
  void _greet() {
    if (_mode == AppMode.metro) {
      _setMascot('chicken_cluck', const Duration(milliseconds: 1100));
      _playSound('sounds/cluck.wav');
    } else if (_mode == AppMode.tap) {
      _setMascot('incog_hide', const Duration(milliseconds: 1300));
      _playSound('sounds/gloups.wav');
    } else {
      _setMascot('cat_meow', const Duration(milliseconds: 800));
      _playSound('sounds/meow.wav');
    }
  }

  String get _idleMascot => switch (_mode) {
    AppMode.listen => 'cat_normal',
    AppMode.tap => 'incog_normal',
    AppMode.metro => 'chicken_normal',
  };

  void _setMascot(String frame, Duration d) {
    _mascotTimer?.cancel();
    _mascotOverride = frame;
    _mascotFrame.value = frame;
    _mascotTimer = Timer(d, () {
      _mascotOverride = null;
      _mascotFrame.value = _idleMascot;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final f in kAllFaces) {
      precacheImage(AssetImage('assets/images/dino_$f.png'), context);
    }
    for (final f in [
      'cat_normal',
      'cat_blink',
      'cat_ear',
      'cat_meow',
      'incog_normal',
      'incog_peek',
      'incog_hide',
      'chicken_normal',
      'chicken_blink',
      'chicken_cluck',
      'psyllo_normal',
      'psyllo_blink',
      'goat_normal',
      'goat_blink',
    ]) {
      precacheImage(AssetImage('assets/images/$f.png'), context);
    }
  }

  @override
  void dispose() {
    _faceTimer?.cancel();
    _longPressTimer?.cancel();
    _accel?.cancel();
    _panicTimer?.cancel();
    _mascotHoldTimer?.cancel();
    _purrPlayer.dispose();
    _egg.dispose();
    _mascotSquish.dispose();
    _metroBeatInBar.dispose();
    for (final n in _paradeSquish.values) {
      n.dispose();
    }
    for (final p in _squishPools.values) {
      p.dispose();
    }
    _metro.dispose();
    _mascotTimer?.cancel();
    _mascotFrame.dispose();
    _blink.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _ticker.dispose();
    _flash.dispose();
    _pulse.dispose();
    _tick.dispose();
    _dinoBounce.dispose();
    _player.dispose();
    _clipPlayer.dispose();
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
      if (_metro.running) _metroToggle();
    }
  }

  // --- Mode ---------------------------------------------------------------------

  void _switchMode() {
    _setMode(_mode == AppMode.listen ? AppMode.tap : AppMode.listen);
  }

  Future<void> _setMode(AppMode mode) async {
    // On attend la fin de _stop() : sinon son "relâche l'écran" arrivait
    // après notre "garde l'écran", et l'écran s'éteignait en mode métronome.
    await _stop();
    _metro.stop();
    _taps.clear();
    _dinoFace = 'head';
    _dinoPressed = false;
    setState(() {
      _mode = mode;
      _displayBpm = null;
      _lastResult = null;
    });
    if (_mode != AppMode.listen) WakelockPlus.enable();
    _mascotOverride = null;
    _greet();
  }

  // --- Métronome ----------------------------------------------------------------

  final ValueNotifier<int> _metroBeatInBar = ValueNotifier(-1);

  void _onMetroBeat(int beat) {
    // L'horloge du beat suit le métronome : tout ce qui danse suit.
    _beatAnchor = DateTime.now();
    _beatPeriodMs = 60000 / _metro.bpm;
    _metroBeatInBar.value = _metro.beatsPerBar > 0
        ? beat % _metro.beatsPerBar
        : -1;
    // Vibration sur chaque temps (option) : plus forte sur le temps fort.
    if (_store.metroVibrate && _store.vibrationOn) {
      final accent = _metro.beatsPerBar > 0 && beat % _metro.beatsPerBar == 0;
      Vibration.vibrate(duration: accent ? 60 : 30);
    }
  }

  void _metroSetBeatsPerBar(int n) {
    _metro.beatsPerBar = n;
    _store.setMetroBeatsPerBar(n);
    setState(() {});
  }

  void _metroToggle() {
    if (_metro.running) {
      _metro.stop();
      _metroBeatInBar.value = -1;
      setState(() {
        _locked = false;
        _beatAnchor = null;
      });
    } else {
      _partySeed = _rng.nextInt(1 << 30);
      _partyStartedAt = _tick.value;
      _metro.start();
      WakelockPlus.enable();
      setState(() => _locked = true);
    }
  }

  void _metroSetBpm(double bpm) {
    _metro.setBpm(bpm);
    _store.setMetroBpm(_metro.bpm);
    if (_metro.running) _beatPeriodMs = 60000 / _metro.bpm;
    setState(() {});
  }

  /// Tap tempo du métronome : moyenne des derniers intervalles.
  void _metroTap() {
    final now = DateTime.now();
    if (_metroTaps.isNotEmpty &&
        now.difference(_metroTaps.last) > _tapTimeout) {
      _metroTaps.clear();
    }
    _metroTaps.add(now);
    if (_metroTaps.length > 9) _metroTaps.removeAt(0);
    if (_metroTaps.length < 2) return;
    var total = 0.0;
    for (var i = 1; i < _metroTaps.length; i++) {
      total +=
          _metroTaps[i].difference(_metroTaps[i - 1]).inMicroseconds / 1000;
    }
    _metroSetBpm(60000 / (total / (_metroTaps.length - 1)));
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
    _silentSamples = 0;
    _musicStopped = false;
    _nothingHeard = false;
    _clipWrite = 0;
    _clipFilled = 0;
    _clippedInWindow = 0;
    _samplesInWindow = 0;
    _saturated = false;
    _dinoFace = 'head';

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
    // En mode secours et métronome, l'écran reste allumé quoi qu'il arrive.
    if (_mode == AppMode.listen) await WakelockPlus.disable();
    _pulse.value = 0;
    _beatAnchor = null;
    if (mounted) {
      setState(() {
        _locked = false;
        _saturated = false;
        if (_mode == AppMode.listen) _dinoFace = 'head';
      });
    }
  }

  void _onAudioChunk(Uint8List bytes) {
    final samples = pcm16ToSamples(bytes);
    if (samples.isEmpty) return;

    // 1. Nourrir le détecteur, et l'anneau des 8 dernières secondes.
    _detector.addSamples(samples);
    for (final v in samples) {
      _clipRing[_clipWrite] = v;
      _clipWrite = (_clipWrite + 1) % _clipSamples;
    }
    _clipFilled = min(_clipFilled + samples.length, _clipSamples);

    // 2. Vu-mètre (RMS → dB) et comptage de la saturation.
    double sumSquares = 0;
    var clipped = 0;
    for (final s in samples) {
      sumSquares += s * s;
      if (s >= 32700 || s <= -32700) clipped++;
    }
    _clippedInWindow += clipped;
    _samplesInWindow += samples.length;
    final rms = sqrt(sumSquares / samples.length);
    final db = 20 * log10(max(rms, 1.0) / 32768.0);
    final level = ((db + 60) / 60).clamp(0.0, 1.0);

    // 3. Estimation périodique.
    _samplesSinceEstimate += samples.length;
    BpmResult? result;
    if (_samplesSinceEstimate >= _estimateEvery) {
      _samplesSinceEstimate = 0;
      _updateSaturation();
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

    // Silence : on compte, et on agit aux deux seuils.
    if (db > -45) {
      _silentSamples = 0;
      if (_musicStopped) {
        // La musique repart : on repart de zéro, proprement.
        _musicStopped = false;
        _detector.reset();
        _history.clear();
      }
      _soundDetected = true;
    } else {
      _silentSamples += samples.length;
      if (_soundDetected &&
          !_musicStopped &&
          !_locked &&
          _silentSamples >= _musicStoppedAfter) {
        _musicStopped = true;
        _detector.reset();
        _history.clear();
        _lastResult = null;
        _displayBpm = null;
        _playSound('sounds/pfff.wav');
      } else if (!_soundDetected && _silentSamples >= _nothingHeardAfter) {
        _nothingHeard = true;
        _stopMic();
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
        .map(
          (c) => '${c.bpm.toStringAsFixed(1)}(${c.score.toStringAsFixed(2)})',
        )
        .join(' ');
    // print et pas debugPrint : on veut la trace aussi en version release,
    // pour calibrer sur de vraies sessions.
    // ignore: avoid_print
    print(
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

  /// Fin de fenêtre : le micro sature-t-il ? Entrée en saturation = le
  /// dino a la nausée + « yark » (pas plus d'une fois toutes les 4 s).
  void _updateSaturation() {
    final ratio = _samplesInWindow == 0
        ? 0.0
        : _clippedInWindow / _samplesInWindow;
    _clippedInWindow = 0;
    _samplesInWindow = 0;
    final now = _saturated;
    _saturated = ratio > 0.01;
    if (_saturated && !now) {
      // On repart de zéro : les estimations faites sur du son écrasé ne
      // valent rien, il faudra 3,5 s de son propre avant un calage.
      _history.clear();
      _dinoFace = 'yark';
      final t = DateTime.now();
      if (t.difference(_lastYark).inSeconds >= 4) {
        _lastYark = t;
        _playSound('sounds/yark.wav');
      }
    } else if (!_saturated && now) {
      _dinoFace = 'head';
    }
  }

  void _updateLock() {
    if (_saturated) return;
    if (_history.length < _historyLength) return;
    final med = _median(_history);
    final spread = (_history.reduce(max) - _history.reduce(min)) / med;

    if (spread < 0.015) {
      _locked = true;
      _celebrate(animalFor(med));
      // On fige l'extrait avant de couper le micro.
      _saveClip(med);
      // Fixé : plus besoin d'écouter. Le bouton repasse en violet ; appuyer
      // dessus relance une recherche.
      _stopMic();
    }
  }

  /// Copie l'anneau dans l'ordre chronologique et l'enregistre avec le BPM.
  Future<void> _saveClip(double bpm) async {
    final n = _clipFilled;
    final pcm = Int16List(n);
    final start = (_clipWrite - n + _clipSamples) % _clipSamples;
    for (var i = 0; i < n; i++) {
      pcm[i] = _clipRing[(start + i) % _clipSamples];
    }
    await _store.add(bpm, pcm, kSampleRate);
    if (mounted) setState(() {});
  }

  void _selectRange(int index) {
    final range = _ranges[index];
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
      // Calé : pendant 3 s le dino crache ses flammes et on ne peut pas
      // le relancer. Ensuite, un tap relance une nouvelle mesure.
      final since = _tapLockedAt == null
          ? _tapLockHold
          : now.difference(_tapLockedAt!);
      if (since < _tapLockHold) return;
      _taps.clear();
      _locked = false;
      _beatAnchor = null;
      _flames.clear();
      setState(() => _displayBpm = null);
      return;
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
          _tapLockedAt = now;
          // Au bout des 3 s : rafraîchir l'écran (halo vert, texte) et
          // prévenir d'une petite vibration.
          Timer(_tapLockHold, () {
            if (!mounted || !_locked) return;
            setState(() {});
            _vibrate(duration: 50);
          });
          _celebrate(kPig);
          _store.setLastTapBpm(bpm);
        }
      }
    }

    setState(() => _displayBpm = bpm);
  }

  // --- Beat -----------------------------------------------------------------

  /// Change le décalage et déplace l'ancre du beat immédiatement, pour que
  /// le point réagisse pendant qu'on règle.
  void _setLatency(int ms) {
    final clamped = ms.clamp(-200, 200);
    final delta = clamped - _store.latencyMs;
    _store.setLatencyMs(clamped);
    if (_beatAnchor != null) {
      _beatAnchor = _beatAnchor!.subtract(Duration(milliseconds: delta));
    }
  }

  void _updateBeatClock(double periodSeconds, double secondsToNextBeat) {
    final now = DateTime.now();
    _beatPeriodMs = periodSeconds * 1000;
    _beatAnchor = now.add(
      Duration(
        milliseconds: (secondsToNextBeat * 1000).round() - _store.latencyMs,
      ),
    );
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    _tick.value = t;
    // Clignement : 130 ms, toutes les 3 à 6 s au hasard.
    if (t >= _nextBlinkAt) {
      _blinkUntil = t + 0.13;
      _nextBlinkAt = t + 3 + _rng.nextDouble() * 3;
      _blink.value = true;
    } else if (_blink.value && t >= _blinkUntil) {
      _blink.value = false;
    }
    // Flammes crachées : tant que le dino est calé en mode secours, une
    // nouvelle toutes les ~70 ms ; chacune vit 0,8 s.
    final spitting = _mode == AppMode.tap && _locked;
    if (spitting && t >= _nextFlameAt) {
      // Pendant les 3 s de blocage : le brasier. Ensuite : quelques
      // flammèches, et le halo vert dit "tu peux taper".
      final intense = !_tapUnlocked;
      _flames.add(
        _Flame(
          t,
          (_rng.nextDouble() - 0.5) * 1.1, // ±32° autour de "droit devant"
          intense ? 70 + _rng.nextDouble() * 60 : 40 + _rng.nextDouble() * 30,
          intense ? 22 + _rng.nextDouble() * 16 : 14 + _rng.nextDouble() * 8,
          (_rng.nextDouble() - 0.5) * 3,
        ),
      );
      _nextFlameAt =
          t +
          (intense
              ? 0.05 + _rng.nextDouble() * 0.05
              : 0.3 + _rng.nextDouble() * 0.3);
    }
    _flames.removeWhere((f) => t - f.born > 0.8);
    // Vie des mascottes : un petit événement toutes les 2,5 à 6 s.
    if (_mascotOverride == null) {
      final tap = _mode == AppMode.tap;
      if (t >= _nextMascotEventAt) {
        if (_mode == AppMode.metro) {
          _mascotFrame.value = 'chicken_blink';
          _mascotEventUntil = t + 0.14;
        } else if (tap) {
          _mascotFrame.value = 'incog_peek';
          _mascotEventUntil = t + 0.7;
        } else {
          final ear = _rng.nextBool();
          _mascotFrame.value = ear ? 'cat_ear' : 'cat_blink';
          _mascotEventUntil = t + (ear ? 0.35 : 0.14);
        }
        _nextMascotEventAt = t + 2.5 + _rng.nextDouble() * 3.5;
      } else if (t >= _mascotEventUntil) {
        final idle = _idleMascot;
        if (_mascotFrame.value != idle) _mascotFrame.value = idle;
      }
    }
    // Mode nuit : 2 min sans rien (pas d'écoute, pas de métronome, pas de
    // calage) → dodo. Réveil au premier tap (voir _wake).
    if (!_asleep &&
        !_isListening &&
        !_metro.running &&
        !_locked &&
        DateTime.now().difference(_lastInteraction).inSeconds >= 120) {
      _asleep = true;
      if (mounted) setState(() {});
    }
    // L'œuf tombe (0,8 s) puis se casse.
    final egg = _egg.value;
    if (egg != null && !_eggBroken) {
      final next = egg + 1 / 48;
      if (next >= 1) {
        _egg.value = 1;
        _eggBroken = true;
        _playSound('sounds/splotch.wav');
        Timer(const Duration(milliseconds: 1200), () {
          _egg.value = null;
          _eggBroken = false;
        });
      } else {
        _egg.value = next;
      }
    }
    // Fin du délire de Psyllo.
    if (_trippyUntil != null && t >= _trippyUntil!) {
      _trippyUntil = null;
      if (mounted) setState(() {});
    }
    // Le rebond du dino et l'écrasement de la mascotte retombent tout seuls.
    if (_dinoBounce.value > 0) {
      _dinoBounce.value = max(0, _dinoBounce.value - 0.08);
    }
    if (_mascotSquish.value > 0) {
      _mascotSquish.value = max(0, _mascotSquish.value - 0.06);
    }
    for (final n in _paradeSquish.values) {
      if (n.value > 0) n.value = max(0, n.value - 0.06);
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

  /// Impose une tête pendant [d], puis remet celle d'avant.
  void _setTemporaryFace(String face, Duration d) {
    _faceTimer?.cancel();
    _faceBefore ??= _dinoFace;
    setState(() => _dinoFace = face);
    _faceTimer = Timer(d, () {
      if (!mounted) return;
      setState(() => _dinoFace = _faceBefore ?? 'head');
      _faceBefore = null;
    });
  }

  /// Easter egg : appui long sur le dino → langue tirée + pet.
  void _easterEgg() {
    _setTemporaryFace('tongue', const Duration(milliseconds: 1400));
    _playSound('sounds/fart.wav');
    _vibrate(duration: 60);
  }

  /// La tête déduite de la situation, quand aucune n'est imposée.
  String _currentFace() {
    if (_dinoFace != 'head') return _dinoFace;
    if (_mode == AppMode.listen && _isListening && !_locked) {
      if (_musicStopped) return 'huh';
      if (!_soundDetected) return 'listen';
      if (_lastResult == null && _dbLevel < -30) return 'huh';
    }
    if (_mode == AppMode.listen && _nothingHeard && !_isListening) {
      return 'huh';
    }
    return 'head';
  }

  int _partySeed = 0;
  double _partyStartedAt = 0;

  Future<void> _celebrate(Animal animal) async {
    _partySeed = _rng.nextInt(1 << 30);
    _partyStartedAt = _tick.value;
    // Il hurle de joie pendant toute la durée du cri.
    _setTemporaryFace('yell', Duration(milliseconds: animal.ms));
    _flash.forward(from: 0);
    _playSound(animal.sound);
    // Deux secousses. Le paquet `vibration` pilote le moteur directement,
    // indépendamment du réglage "vibration au toucher" du téléphone.
    await _vibrate(pattern: [0, 180, 120, 180]);
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
        if (_mode == AppMode.metro) ...[
          _buildSubtitle('METRONOME EDITION', fire: false),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text(
                '🌭 mode mon cul sur la commode 🌭',
                style: TextStyle(
                  fontSize: 20,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE6C9FF),
                ),
              ),
            ),
          ),
          _buildMascot(size: 100),
        ] else ...[
          _buildSubtitle('PASTELLE EDITION', fire: fire),
          if (!fire) _buildMascot(),
        ],
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMascot(),
              const SizedBox(width: 6),
              const Text(
                'je l\'ai entendu faire prout..',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFFFFD9A0),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// La mascotte sous le sous-titre. Une fois calé, elle bouge sur le
  /// beat : le chat hoche la tête, l'incognito tape du journal.
  Widget _buildMascot({double size = 90}) {
    final tap = _mode == AppMode.tap;
    return SizedBox(
      height: size + 6,
      child: ValueListenableBuilder<String>(
        valueListenable: _mascotFrame,
        builder: (context, frame, _) {
          return ValueListenableBuilder<double>(
            valueListenable: _pulse,
            builder: (context, pulse, child) {
              final onBeat = _locked && _beatAnchor != null;
              final side = _beatIndex.isEven ? 1.0 : -1.0;
              // Chat : hochement ; incognito : le journal tape (rebond).
              final angle = onBeat && !tap ? side * 0.18 * pulse : 0.0;
              final dy = onBeat && tap
                  ? 6 * pulse
                  : (onBeat ? -4 * pulse : 0.0);
              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform.rotate(angle: angle, child: child),
              );
            },
            // Un appui l'écrase (squish), il reprend sa forme tout seul.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                _mascotSquish.value = 1;
                if (_store.soundsOn) {
                  _squishPools[switch (_mode) {
                        AppMode.listen => 'cat',
                        AppMode.tap => 'incog',
                        AppMode.metro => 'chicken',
                      }]
                      ?.start();
                }
                if (_mode == AppMode.metro) _selectMetroSound('chicken');
                _mascotHoldTimer?.cancel();
                _mascotHoldTimer = Timer(
                  const Duration(milliseconds: 500),
                  _mascotHold,
                );
              },
              onPointerUp: (_) => _mascotRelease(),
              onPointerCancel: (_) => _mascotRelease(),
              child: ValueListenableBuilder<double>(
                valueListenable: _mascotSquish,
                builder: (context, sq, child) => Transform.scale(
                  scaleX: 1 + 0.35 * sq,
                  scaleY: 1 - 0.4 * sq,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
                child: Image.asset(
                  'assets/images/$frame.png',
                  height: size,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            ),
          );
        },
      ),
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
    final text = _show420
        ? '420'
        : (_displayBpm == null ? '—' : _displayBpm!.toStringAsFixed(1));

    if (_show420) {
      return GestureDetector(
        onTap: _digitTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RainbowText(text, style: style),
            const Text('🍄', style: TextStyle(fontSize: 40)),
          ],
        ),
      );
    }
    if (!_locked) {
      return GestureDetector(
        onTap: _digitTap,
        child: Text(text, style: style),
      );
    }

    // Calé : pendant le flash, les couleurs tournent et le texte clignote ;
    // ensuite, arc-en-ciel fixe.
    return GestureDetector(
      onTap: _digitTap,
      child: AnimatedBuilder(
        animation: _flash,
        builder: (context, _) {
          final t = _flash.value;
          final flashing = _flash.isAnimating && _store.lightsOn;
          final blink = flashing ? (sin(t * 2 * pi * 9) > 0 ? 1.0 : 0.3) : 1.0;
          return Opacity(
            opacity: blink,
            child: RainbowText(text, style: style, shift: flashing ? t * 3 : 0),
          );
        },
      ),
    );
  }

  /// « BPM », avec l'animal du tempo qui danse à côté une fois calé.
  Widget _buildBpmLabel(ThemeData theme) {
    final bpm = _displayBpm;
    if (!_locked || bpm == null) {
      return Text('BPM', style: theme.textTheme.titleLarge);
    }
    final animal = _mode == AppMode.tap ? kPig : animalFor(bpm);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _pulse,
          builder: (context, pulse, _) {
            final side = _beatIndex.isEven ? 1.0 : -1.0;
            return Transform.translate(
              offset: Offset(0, -10 * pulse),
              child: Transform.rotate(
                angle: side * 0.35 * pulse,
                child: Transform.scale(
                  scale: 1 + 0.3 * pulse,
                  child: Text(
                    animal.emoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Text('BPM', style: theme.textTheme.titleLarge),
      ],
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
    if (_saturated && _isListening) {
      glow = kAlertRed;
    } else if (tap && _locked && _tapUnlocked) {
      glow = kGreenSign;
    } else if (tap) {
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

    // En mode secours, chaque tap donne au dino une nouvelle tête (au
    // hasard parmi trois, jamais deux fois la même de suite) qu'il garde
    // jusqu'au tap suivant. Il ne s'aplatit que pendant l'appui.
    void squish() {
      if (!tap) return;
      var next = 'squish${1 + _rng.nextInt(3)}';
      while (next == _dinoFace) {
        next = 'squish${1 + _rng.nextInt(3)}';
      }
      setState(() {
        _dinoFace = next;
        _dinoPressed = true;
      });
    }

    void unsquish() {
      if (!tap) return;
      setState(() => _dinoPressed = false);
    }

    final squished = tap && _dinoPressed;

    final face = _currentFace();
    // Tête penchée quand il tend l'oreille.
    final tilt = face == 'listen' ? -0.14 : 0.0;
    // Pendant l'analyse, les pupilles sautent d'un côté à l'autre sur le
    // beat ; une fois calé, c'est toute la tête qui hoche.
    final analysing = !tap && _isListening && !_locked && _lastResult != null;
    final nodding = _locked && _beatAnchor != null;

    // Listener plutôt que GestureDetector : l'événement brut du doigt,
    // sans délai d'arbitrage (jusqu'à 100 ms quand un appui long est aussi
    // possible) et sans annulation si le doigt glisse. Pour le tap tempo,
    // c'est la différence entre "ça rate" et "ça répond".
    final dino = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        squish();
        onTap();
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 600), _easterEgg);
      },
      onPointerUp: (_) {
        unsquish();
        _longPressTimer?.cancel();
      },
      onPointerCancel: (_) {
        unsquish();
        _longPressTimer?.cancel();
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _tick,
        builder: (context, t, child) {
          final bounce = _dinoBounce.value;
          final pulse = _pulse.value;
          final side = _beatIndex.isEven ? 1.0 : -1.0;
          // Respiration : ±2 %, lente.
          final breath = 1 + 0.02 * sin(t * 1.8);
          final nod = nodding ? side * 0.09 * pulse : 0.0;
          return Transform.rotate(
            angle: tilt + nod,
            child: Transform.scale(
              scaleX: breath * (1 + (squished ? 0.12 : 0.0)),
              scaleY: breath * (1 - 0.15 * bounce) * (squished ? 0.82 : 1.0),
              child: child,
            ),
          );
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
                spreadRadius: tap && _locked && _tapUnlocked
                    ? 12
                    : (active ? 4 : 1),
              ),
            ],
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: _blink,
            builder: (context, blink, _) {
              return ValueListenableBuilder<double>(
                valueListenable: _pulse,
                builder: (context, pulse, _) {
                  final side = _beatIndex.isEven ? 1.0 : -1.0;
                  final pupil = analysing
                      ? Offset(side * (0.35 + 0.65 * pulse), 0.15)
                      : Offset.zero;
                  return DinoFace(
                    face: face,
                    size: 180,
                    pupil: pupil,
                    blink: blink,
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    // Les flammes se dessinent par-dessus, dans une zone plus large que
    // le dino pour pouvoir en sortir. Elles ne captent pas les taps.
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          dino,
          IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: _tick,
              builder: (context, t, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final f in _flames) _buildFlameParticle(f, t),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlameParticle(_Flame f, double t) {
    final age = t - f.born; // 0 → 0,8 s
    final life = (age / 0.8).clamp(0.0, 1.0);
    // Départ à la bouche (centre + 50 px vers le bas), trajet vers le bas
    // et l'avant, en grossissant puis en s'effaçant.
    final dist = f.speed * age;
    final x = 150 + sin(f.angle) * dist;
    final y = 150 + 50 + cos(f.angle) * dist * 0.6;
    final scale = 0.5 + 1.4 * life;
    final opacity = life < 0.7 ? 1.0 : 1 - (life - 0.7) / 0.3;
    return Positioned(
      left: x - f.size / 2,
      top: y - f.size / 2,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: f.spin * life,
          child: Transform.scale(
            scale: scale,
            child: Text('🔥', style: TextStyle(fontSize: f.size)),
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
            _tapUnlocked ? 'Tape-le pour recommencer !' : 'Laisse-le cracher…',
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
    } else if (!_isListening && _nothingHeard) {
      lines = [
        Text('Rien entendu, micro coupé', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text('Tape le dino quand ça joue', style: theme.textTheme.bodySmall),
      ];
    } else if (!_isListening) {
      lines = [
        Text(
          'Appuie sur le dino quand le son a pété',
          style: theme.textTheme.bodyLarge,
        ),
      ];
    } else if (_saturated) {
      lines = [
        const Text(
          'ÇA SATURE ! Éloigne le téléphone',
          style: TextStyle(
            color: kAlertRed,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pas de calage tant que le son est écrasé',
          style: theme.textTheme.bodySmall,
        ),
      ];
    } else if (_musicStopped) {
      lines = [
        Text('La musique s\'est arrêtée', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          'J\'écoute toujours… relance un son',
          style: theme.textTheme.bodySmall,
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
    } else if (_dbLevel < -30 && result == null) {
      lines = [
        Text(
          'Balance le son, sois pas timide !',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Son faible (${_dbLevel.toStringAsFixed(0)} dB) · analyse… ${buffered.toStringAsFixed(1)} s',
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

  /// Le panneau vert HISTO, en bas au centre.
  Widget _buildHistorySign() {
    return GestureDetector(
      onTap: _showHistory,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        decoration: BoxDecoration(
          color: kGreenSign,
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
        child: const Text(
          'HISTO',
          style: TextStyle(
            fontFamily: 'RubikSprayPaint',
            fontSize: 22,
            height: 1.0,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  /// Mode secours : le dernier BPM tapé, en bas au centre.
  Widget _buildLastTap() {
    final last = _store.lastTapBpm;
    if (last == null) return const SizedBox.shrink();
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => const LinearGradient(
        colors: kFire,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect),
      child: Text(
        'Dernier : ${fmtBpm(last)}',
        style: const TextStyle(
          fontFamily: 'RubikSprayPaint',
          fontSize: 26,
          height: 1.0,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _togglePlay(HistoryEntry e) async {
    if (_playingFile == e.file) {
      await _clipPlayer.stop();
      _playingFile = null;
    } else {
      await _clipPlayer.stop();
      _playingFile = e.file;
      await _clipPlayer.play(DeviceFileSource(e.file));
    }
  }

  /// Popup Historique : les 5 derniers calages, avec date, BPM, ▶ et 🗑.
  Future<void> _showHistory({bool pick = false}) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: kGreenSign,
              brightness: Brightness.dark,
            ),
          ),
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
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
                  color: const Color(0xFF0E1F12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    final entries = _store.entries;
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RainbowText(
                            pick ? 'Reprendre un tempo' : 'Historique',
                            style: Theme.of(context).textTheme.titleLarge!
                                .copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                          ),
                          const SizedBox(height: 8),
                          if (entries.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Rien pour l\'instant — cale un son !',
                              ),
                            ),
                          for (final e in entries)
                            ListTile(
                              dense: true,
                              onTap: pick
                                  ? () {
                                      _metroSetBpm(e.bpm);
                                      Navigator.of(context).pop();
                                    }
                                  : null,
                              leading: IconButton(
                                iconSize: 32,
                                color: kGreenSign,
                                icon: Icon(
                                  _playingFile == e.file
                                      ? Icons.stop_circle
                                      : Icons.play_circle,
                                ),
                                onPressed: () async {
                                  await _togglePlay(e);
                                  setDialogState(() {});
                                },
                              ),
                              title: Text(
                                '${animalFor(e.bpm).emoji}  ${fmtBpm(e.bpm)} BPM',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              subtitle: Text(_fmtDate(e.at)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.share),
                                    color: kGreenSign,
                                    tooltip: 'Partager le son et son BPM',
                                    onPressed: () => _shareEntry(e),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.redAccent,
                                    onPressed: () async {
                                      if (_playingFile == e.file) {
                                        await _clipPlayer.stop();
                                        _playingFile = null;
                                      }
                                      await _store.remove(e);
                                      setDialogState(() {});
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    // Fermer le popup arrête la lecture.
    await _clipPlayer.stop();
    _playingFile = null;
  }

  /// Partage l'extrait audio (WAV 8 s) avec son BPM et le lien de l'appli.
  Future<void> _shareEntry(HistoryEntry e) async {
    final text =
        '${fmtBpm(e.bpm)} BPM 🔥\n'
        'Trouvé avec TOMATOZOR Pastelle Edition — gratuit ici : $kDownloadUrl';
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [XFile(e.file, mimeType: 'audio/wav')],
        subject: 'TOMATOZOR — ${fmtBpm(e.bpm)} BPM',
      ),
    );
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  /// Section Ambiance des options : lumières, sons, vibrations, et la
  /// vibration sur chaque temps du métronome.
  Widget _buildAmbianceControls(void Function(void Function()) setDialogState) {
    Widget row(
      String title,
      String subtitle,
      IconData icon,
      bool value,
      void Function(bool) onChanged,
    ) {
      return SwitchListTile(
        dense: true,
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        value: value,
        onChanged: (v) {
          onChanged(v);
          setDialogState(() {});
          if (mounted) setState(() {});
        },
      );
    }

    return Column(
      children: [
        const Text('Ambiance', style: TextStyle(fontWeight: FontWeight.bold)),
        row(
          'Lumières',
          'néons, flashs',
          Icons.flash_on,
          _store.lightsOn,
          (v) => _store.setAmbiance(lights: v),
        ),
        row(
          'Sons',
          'cris, squish, accueil (pas les clics du métronome)',
          Icons.music_note,
          _store.soundsOn,
          (v) => _store.setAmbiance(sounds: v),
        ),
        row(
          'Vibrations',
          'calage, déblocage, easter eggs',
          Icons.vibration,
          _store.vibrationOn,
          (v) => _store.setAmbiance(vibration: v),
        ),
        row(
          'Métronome : vibrer sur chaque temps',
          'pour bosser en silence, téléphone dans la poche',
          Icons.watch_later_outlined,
          _store.metroVibrate,
          (v) => _store.setAmbiance(metroVibrate: v),
        ),
      ],
    );
  }

  /// Réglage du décalage du point de beat, avec un petit point témoin qui
  /// bat en même temps que le grand.
  Widget _buildLatencyControl(void Function(void Function()) setDialogState) {
    final ms = _store.latencyMs;
    void set(int v) {
      _setLatency(v);
      setDialogState(() {});
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _pulse,
              builder: (context, pulse, _) {
                final size = 12 + 14 * pulse;
                return SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(
                          const Color(0xFF7B2C6B),
                          kPink,
                          pulse,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            const Text(
              'Décalage du point de beat',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const Text(
          'Point en retard sur la musique → augmente',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => set(ms - 10),
            ),
            Expanded(
              child: Slider(
                value: ms.toDouble(),
                min: -200,
                max: 200,
                divisions: 40,
                label: '${ms >= 0 ? '+' : ''}$ms ms',
                onChanged: (v) => set(v.round()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => set(ms + 10),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${ms >= 0 ? '+' : ''}$ms ms',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: ms == HistoryStore.defaultLatencyMs
                  ? null
                  : () => set(HistoryStore.defaultLatencyMs),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Réinitialiser'),
            ),
          ],
        ),
      ],
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
                    return SingleChildScrollView(
                      child: Column(
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
                          for (var i = 0; i < _ranges.length; i++)
                            CheckboxListTile(
                              value: i == _rangeIndex,
                              activeColor: kRainbow[i % kRainbow.length],
                              title: Text(
                                _ranges[i].label,
                                style: TextStyle(
                                  fontWeight: i == _rangeIndex
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: i == 0
                                  ? const Text(
                                      'Détection large, a priori 90-180',
                                    )
                                  : null,
                              dense: true,
                              onChanged: (_) {
                                _selectRange(i);
                                _rangeKonami(i);
                                setDialogState(() {});
                              },
                            ),
                          const Divider(height: 20),
                          _buildLatencyControl(setDialogState),
                          const Divider(height: 20),
                          _buildAmbianceControls(setDialogState),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _showTutorial();
                            },
                            icon: const Icon(Icons.school_outlined, size: 18),
                            label: const Text('Revoir le tutoriel'),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
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
    if (_mode == AppMode.metro) {
      return IconButton(
        onPressed: () => _setMode(AppMode.listen),
        tooltip: 'Retour au mode micro',
        iconSize: 28,
        color: kPink,
        icon: const Icon(Icons.mic),
      );
    }
    final tap = _mode == AppMode.tap;
    return IconButton(
      onPressed: _switchMode,
      tooltip: tap ? 'Retour au mode micro' : 'Mode de secours (tap tempo)',
      iconSize: 28,
      color: tap ? kPink : kAlertRed,
      icon: Icon(tap ? Icons.mic : Icons.warning_rounded),
    );
  }

  // --- Interface du métronome -------------------------------------------------------

  /// Des champignons qui dérivent lentement dans le fond, à moitié
  /// transparents, et qui tournent : l'ambiance psyché.
  Widget _buildMushroomDrift() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: _tick,
          builder: (context, t, _) {
            return LayoutBuilder(
              builder: (context, c) {
                final rng = Random(77);
                return Stack(
                  children: [
                    for (var i = 0; i < 9; i++)
                      Builder(
                        builder: (_) {
                          final speed = 0.02 + rng.nextDouble() * 0.03;
                          final x0 = rng.nextDouble();
                          final phase = rng.nextDouble() * 6.28;
                          final size = 28 + rng.nextDouble() * 30;
                          final y =
                              ((1 - ((t * speed + rng.nextDouble()) % 1.0)) *
                                  (c.maxHeight + 80)) -
                              40;
                          final x =
                              (x0 + 0.06 * sin(t * 0.7 + phase)) *
                              (c.maxWidth - size);
                          return Positioned(
                            left: x,
                            top: y,
                            child: Opacity(
                              opacity: 0.35,
                              child: Transform.rotate(
                                angle: sin(t * 0.5 + phase) * 0.4,
                                child: Text(
                                  '🍄',
                                  style: TextStyle(fontSize: size),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetroPanel(BuildContext context) {
    final theme = Theme.of(context);
    final bpm = _metro.bpm;
    final tier = tierFor(bpm);
    final accent = kMetroAccents[tier];
    final running = _metro.running;

    Widget roundButton(IconData icon, VoidCallback onTap, {double size = 44}) {
      return SizedBox(
        width: size,
        height: size,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: accent.withValues(alpha: 0.25),
            foregroundColor: Colors.white,
          ),
          child: Icon(icon, size: size * 0.55),
        ),
      );
    }

    final panel = Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent, width: 3),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: running ? 0.6 : 0.3),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              roundButton(Icons.remove, () => _metroSetBpm(bpm - 1), size: 32),
              const SizedBox(width: 12),
              Text(
                bpm.round().toString(),
                style: theme.textTheme.displayLarge!.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 12),
              roundButton(Icons.add, () => _metroSetBpm(bpm + 1), size: 32),
            ],
          ),
          Text(
            _metro.sound == 'wood'
                ? 'BPM · clic bois'
                : 'BPM · son : ${_soundLabel(_metro.sound)}',
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              thumbColor: accent,
              inactiveTrackColor: Colors.white24,
            ),
            child: Slider(
              value: bpm.clamp(Metronome.minBpm, Metronome.maxBpm),
              min: Metronome.minBpm,
              max: Metronome.maxBpm,
              onChanged: (v) => _metroSetBpm(v.roundToDouble()),
            ),
          ),
          // Mesure : temps fort tous les n temps, et les points qui
          // s'allument au fil de la mesure.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (label, n) in [
                ('4/4', 4),
                ('3/4', 3),
                ('6/8', 6),
                ('2/4', 2),
                ('—', 0),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    selected: _metro.beatsPerBar == n,
                    selectedColor: accent.withValues(alpha: 0.5),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onSelected: (_) => _metroSetBeatsPerBar(n),
                  ),
                ),
            ],
          ),
          if (_metro.beatsPerBar > 0)
            ValueListenableBuilder<int>(
              valueListenable: _metroBeatInBar,
              builder: (context, current, _) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _metro.beatsPerBar; i++)
                    Container(
                      width: i == 0 ? 12 : 9,
                      height: i == 0 ? 12 : 9,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == current ? accent : Colors.white24,
                        boxShadow: i == current
                            ? [BoxShadow(color: accent, blurRadius: 8)]
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _metroTap(),
                child: OutlinedButton.icon(
                  onPressed: () {}, // géré par le Listener, sans délai
                  icon: const Icon(Icons.touch_app),
                  label: const Text('TAP'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: accent, width: 2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _showHistory(pick: true),
                icon: const Icon(Icons.history),
                label: const Text('HISTO'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: kGreenSign, width: 2),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                height: 44,
                child: FilledButton(
                  onPressed: _metroToggle,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: running ? kAlertRed : kGreenSign,
                    foregroundColor: Colors.white,
                  ),
                  child: Icon(
                    running ? Icons.stop : Icons.play_arrow,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: panel,
    );
  }

  /// Un personnage de la parade (image dessinée ou emoji), tous à la même
  /// taille. Il danse sur le beat (plus fort si c'est l'animal de la
  /// tranche en cours), se balance au repos, cligne des yeux, et un tap
  /// l'écrase avec son bruit à lui.
  Widget _buildParadeItem(String name, int index, {int? tier}) {
    const size = 60.0;
    final squish = _paradeSquish.putIfAbsent(index, () => ValueNotifier(0));
    final currentTier = tierFor(_metro.bpm);
    final star = tier == currentTier;
    final selected = _metro.sound == name;

    return GestureDetector(
      onTapDown: (_) {
        squish.value = 1;
        if (_store.soundsOn) _squishPools[name]?.start();
        _selectMetroSound(name);
      },
      onLongPress: name == 'psyllo'
          ? () {
              setState(() => _trippyUntil = _tick.value + 3);
              _playSound('sounds/giggle.wav');
            }
          : null,
      child: ValueListenableBuilder<double>(
        valueListenable: _tick,
        builder: (context, t, _) {
          final pulse = _metro.running ? _pulse.value : 0.0;
          final side = (_beatIndex + index).isEven ? 1.0 : -1.0;
          final amp = [0.35, 0.6, 0.85, 1.2][currentTier] * (star ? 1.0 : 0.6);
          final sway = _metro.running ? 0.0 : 0.06 * sin(t * 1.4 + index * 1.3);
          final bob = _metro.running ? 0.0 : 2 * sin(t * 2.1 + index);
          final blinking = _asleep || (t + index) % (3.7 + index * 0.6) < 0.15;
          final Widget img = switch (name) {
            'dino' => DinoFace(face: 'head', size: size, blink: blinking),
            'pig' => const Text('🐷', style: TextStyle(fontSize: 50)),
            'unicorn' => const Text('🦄', style: TextStyle(fontSize: 50)),
            _ => Image.asset(
              'assets/images/${name}_${blinking ? (name == 'incog' ? 'peek' : 'blink') : 'normal'}.png',
              height: size,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          };
          return Transform.translate(
            offset: Offset(0, -22 * amp * pulse + bob),
            child: Transform.rotate(
              angle: side * 0.4 * amp * pulse + sway,
              child: Transform.scale(
                scale: (star ? 1.15 : 1.0) * (1 + 0.3 * amp * pulse),
                child: ValueListenableBuilder<double>(
                  valueListenable: squish,
                  builder: (context, sq, child) => Transform.scale(
                    scaleX: 1 + 0.35 * sq,
                    scaleY: 1 - 0.4 * sq,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                  // L'animal dont le son est choisi a un halo.
                  child: selected
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: kMetroAccents[currentTier].withValues(
                                  alpha: 0.9,
                                ),
                                blurRadius: 22,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                          child: img,
                        )
                      : img,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _soundLabel(String name) => switch (name) {
    'cat' => 'chat 🐱',
    'incog' => 'incognito 🕵️',
    'chicken' => 'poulet 🐔',
    'dino' => 'dino 🦖',
    'goat' => 'chèvre 🐐',
    'pig' => 'cochon 🐷',
    'unicorn' => 'licorne 🦄',
    'psyllo' => 'Psyllo 🍄',
    _ => name,
  };

  /// Un tap sur un animal choisit son son pour le métronome ; un second
  /// tap sur le même revient au bois.
  void _selectMetroSound(String name) {
    final next = _metro.sound == name ? 'wood' : name;
    _metro.setSound(next);
    _store.setMetroSound(next);
    setState(() {});
  }

  /// La scène du métronome : le panneau au centre, les animaux éparpillés
  /// autour à des positions fixes (fractions de la zone), chacun penché
  /// à sa façon pour casser l'alignement.
  Widget _buildMetroScene(BuildContext context) {
    // Une rangée au-dessus du panneau, une en dessous : impossible de
    // chevaucher le métronome. Décalages verticaux et inclinaisons variés
    // pour casser l'alignement.
    Widget spot(String name, int index, double dy, double tilt, {int? tier}) {
      return Transform.translate(
        offset: Offset(0, dy),
        child: Transform.rotate(
          angle: tilt,
          child: _buildParadeItem(name, index, tier: tier),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            spot('cat', 0, 8, -0.15),
            spot('goat', 2, -10, 0.12, tier: 3),
            spot('unicorn', 1, 4, 0.2, tier: 2),
            spot('dino', 3, -6, -0.1),
          ],
        ),
        const SizedBox(height: 14),
        _buildMetroPanel(context),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            spot('pig', 4, 6, -0.2, tier: 1),
            spot('incog', 5, -8, 0.08),
            spot('psyllo', 6, 10, 0.18),
          ],
        ),
      ],
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
        brightness: _mode == AppMode.listen
            ? Brightness.light
            : Brightness.dark,
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
                colors: switch (_mode) {
                  AppMode.listen => kKawaiiBackground,
                  AppMode.tap => kFireBackground,
                  AppMode.metro => kMetroBackground,
                },
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _wake(),
                child: _buildTrippy(
                  Stack(
                    children: [
                      if (_mode == AppMode.metro) _buildMushroomDrift(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            _buildHeader(context),
                            const Spacer(),

                            if (_mode == AppMode.metro) ...[
                              Expanded(
                                flex: 20,
                                child: _buildMetroScene(context),
                              ),
                            ] else ...[
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
                              _buildBpmLabel(theme),
                              _buildBeatDot(),
                              _buildStatus(context),
                              const Spacer(),

                              // --- Le bouton, au centre ------------------------------
                              _buildDinoButton(),
                              const Spacer(),
                            ],

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
                      if (_mode == AppMode.listen)
                        Positioned(
                          left: 8,
                          bottom: 72,
                          child: _buildOptionsSign(),
                        ),
                      if (_mode != AppMode.metro)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 72,
                          child: Center(
                            child: tap ? _buildLastTap() : _buildHistorySign(),
                          ),
                        ),
                      if (_mode == AppMode.listen)
                        Positioned(
                          right: 52,
                          bottom: 74,
                          child: IconButton(
                            onPressed: () => _setMode(AppMode.metro),
                            tooltip: 'Mode Métronome',
                            iconSize: 26,
                            color: const Color(0xFF4FA3FF),
                            icon: const Icon(Icons.av_timer),
                          ),
                        ),
                      Positioned(
                        right: 4,
                        bottom: 72,
                        child: _buildModeToggle(),
                      ),
                      // Mode nuit : voile sombre et Zzz.
                      if (_asleep)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.55),
                              child: ValueListenableBuilder<double>(
                                valueListenable: _tick,
                                builder: (context, t, _) => Stack(
                                  children: [
                                    for (var i = 0; i < 3; i++)
                                      Positioned(
                                        left:
                                            40.0 +
                                            i * 110 +
                                            10 * sin(t * 1.3 + i),
                                        top:
                                            120.0 +
                                            i * 40 -
                                            30 * ((t * 0.4 + i * 0.33) % 1.0),
                                        child: Opacity(
                                          opacity:
                                              1 - ((t * 0.4 + i * 0.33) % 1.0),
                                          child: Text(
                                            'Z' * (i + 1),
                                            style: TextStyle(
                                              fontFamily: 'RubikSprayPaint',
                                              fontSize: 24.0 + i * 10,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // L'œuf du poulet qui tombe, puis l'omelette.
                      ValueListenableBuilder<double?>(
                        valueListenable: _egg,
                        builder: (context, egg, _) {
                          if (egg == null) return const SizedBox.shrink();
                          return LayoutBuilder(
                            builder: (context, c) => Positioned(
                              left: c.maxWidth / 2 - 20,
                              top: 150 + (c.maxHeight - 230) * egg * egg,
                              child: IgnorePointer(
                                child: Text(
                                  _eggBroken ? '🍳' : '🥚',
                                  style: const TextStyle(fontSize: 40),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // Ambiance réduite : petites icônes barrées, discrètes.
                      if (!_store.soundsOn || !_store.lightsOn)
                        Positioned(
                          right: 10,
                          top: 6,
                          child: Opacity(
                            opacity: 0.6,
                            child: Row(
                              children: [
                                if (!_store.lightsOn)
                                  const Icon(Icons.flash_off, size: 18),
                                if (!_store.soundsOn)
                                  const Icon(Icons.music_off, size: 18),
                              ],
                            ),
                          ),
                        ),
                      // La fête : néons de toutes les couleurs tant que ça danse
                      // (calé, beat en cours), dans les deux modes.
                      if (_locked && _beatAnchor != null && _store.lightsOn)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _tick,
                              builder: (context, t, _) {
                                return CustomPaint(
                                  painter: _PartyPainter(
                                    (t - _partyStartedAt),
                                    _partySeed,
                                    count: _mode == AppMode.metro
                                        ? [8, 18, 30, 48][tierFor(_metro.bpm)]
                                        : 42,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Délire de Psyllo : les couleurs tournent et tout ondule pendant 3 s.
  Widget _buildTrippy(Widget child) {
    if (_trippyUntil == null) return child;
    return ValueListenableBuilder<double>(
      valueListenable: _tick,
      builder: (context, t, _) {
        final h = (t * 1.5) % 1.0 * 2 * pi;
        // Matrice de rotation de teinte (approximation classique).
        final c = cos(h), s = sin(h);
        final m = <double>[
          0.213 + c * 0.787 - s * 0.213,
          0.715 - c * 0.715 - s * 0.715,
          0.072 - c * 0.072 + s * 0.928,
          0,
          0,
          0.213 - c * 0.213 + s * 0.143,
          0.715 + c * 0.285 + s * 0.140,
          0.072 - c * 0.072 - s * 0.283,
          0,
          0,
          0.213 - c * 0.213 - s * 0.787,
          0.715 - c * 0.715 + s * 0.715,
          0.072 + c * 0.928 + s * 0.072,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(m),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(0, 1, 0.06 * sin(t * 4))
              ..scaleByDouble(
                1 + 0.03 * sin(t * 3),
                1 + 0.03 * sin(t * 3),
                1,
                1,
              ),
            child: child,
          ),
        );
      },
    );
  }
}
