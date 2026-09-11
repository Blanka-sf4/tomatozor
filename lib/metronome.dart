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

  /// Son courant : 'wood' (bois) ou le nom d'un animal.
  String sound = 'wood';

  bool get running => _timer != null;

  /// Charge les deux clics dans des pools à faible latence.
  Future<void> init() => setSound(sound);

  /// Change le son (à chaud si ça tourne) : 'wood' → click.wav / click_hi.wav,
  /// sinon `click_NOM.wav` / `click_NOM_hi.wav`.
  Future<void> setSound(String name) async {
    sound = name;
    final base = name == 'wood' ? 'sounds/click' : 'sounds/click_$name';
    final ctx = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
        .build();
    final lo = await AudioPool.create(
      source: AssetSource('$base.wav'),
      maxPlayers: 4,
      audioContext: ctx,
    );
    final hi = await AudioPool.create(
      source: AssetSource('${base}_hi.wav'),
      maxPlayers: 2,
      audioContext: ctx,
    );
    // Si un autre setSound a été appelé entre-temps, on jette celui-ci.
    if (sound != name) {
      await lo.dispose();
      await hi.dispose();
      return;
    }
    final oldLo = _lo, oldHi = _hi;
    _lo = lo;
    _hi = hi;
    await oldLo?.dispose();
    await oldHi?.dispose();
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
