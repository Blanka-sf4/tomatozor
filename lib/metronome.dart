import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Métronome : clics bois planifiés sur une horloge absolue (pas de dérive),
/// temps fort tous les [beatsPerBar] temps.
class Metronome {
  Metronome({required this.onBeat});

  /// Appelé à chaque clic avec le numéro du temps (0 = temps fort).
  final void Function(int beat) onBeat;

  double bpm = 120;
  int beatsPerBar = 4;

  static const double minBpm = 30;
  static const double maxBpm = 380;

  AudioPool? _lo;
  AudioPool? _hi;
  Timer? _timer;
  DateTime? _next;
  int _beat = 0;

  bool get running => _timer != null;

  /// Charge les deux clics dans des pools à faible latence.
  Future<void> init() async {
    final ctx = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
        .build();
    _lo = await AudioPool.create(
      source: AssetSource('sounds/click.wav'),
      maxPlayers: 4,
      audioContext: ctx,
    );
    _hi = await AudioPool.create(
      source: AssetSource('sounds/click_hi.wav'),
      maxPlayers: 2,
      audioContext: ctx,
    );
  }

  void start() {
    if (running) return;
    _beat = 0;
    _next = DateTime.now().add(const Duration(milliseconds: 60));
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setBpm(double value) {
    bpm = value.clamp(minBpm, maxBpm);
  }

  void _schedule() {
    final wait = _next!.difference(DateTime.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _fire);
  }

  void _fire() {
    final accent = beatsPerBar > 0 && _beat % beatsPerBar == 0;
    (accent ? _hi : _lo)?.start();
    onBeat(_beat);
    _beat++;
    // Le prochain temps se calcule depuis le précédent, pas depuis "maintenant" :
    // le retard éventuel du timer ne s'accumule pas.
    _next = _next!.add(Duration(microseconds: (60e6 / bpm).round()));
    // Si on a pris beaucoup de retard (appli gelée), on se recale.
    if (_next!.isBefore(DateTime.now())) _next = DateTime.now();
    _schedule();
  }

  Future<void> dispose() async {
    stop();
    await _lo?.dispose();
    await _hi?.dispose();
  }
}
