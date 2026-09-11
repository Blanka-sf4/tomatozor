import 'dart:math';
import 'dart:typed_data';

/// Un tempo candidat : sa valeur et la force de sa périodicité (0..1+).
class BpmCandidate {
  const BpmCandidate(this.bpm, this.score);
  final double bpm;
  final double score;
}

/// Résultat d'une estimation.
class BpmResult {
  const BpmResult({
    required this.bpm,
    required this.confidence,
    required this.candidates,
    required this.periodSeconds,
    required this.secondsToNextBeat,
  });

  /// Le tempo retenu.
  final double bpm;

  /// Durée d'un temps, en secondes (= 60 / bpm).
  final double periodSeconds;

  /// Délai estimé entre la fin du son analysé et le prochain temps.
  /// Sert à faire pulser un indicateur en rythme.
  final double secondsToNextBeat;

  /// Force de la périodicité au tempo retenu (0 = rien, 1 = parfait).
  final double confidence;

  /// Les autres pics trouvés, du plus fort au plus faible.
  final List<BpmCandidate> candidates;
}

/// Détecteur de tempo en temps réel.
///
/// Pipeline :
///   échantillons → passe-bas → énergie par trame → flux d'onsets
///   → autocorrélation → pic → interpolation → BPM
///
/// On lui pousse du son avec [addSamples] et on lui demande une estimation
/// avec [estimate] quand on veut. Aucune dépendance Flutter.
class BpmDetector {
  BpmDetector({
    this.sampleRate = 44100,
    this.hopSize = 256,
    this.bufferSeconds = 8.0,
    this.minBpm = 60,
    this.maxBpm = 450,
    double lowPassHz = 200,
  }) : _bufferFrames = (bufferSeconds * sampleRate / hopSize).round(),
       // Filtre passe-bas à un pôle : y += a * (x - y). Le coefficient
       // découle de la fréquence de coupure voulue.
       _lpAlpha = 1 - exp(-2 * pi * lowPassHz / sampleRate) {
    _onsets = Float64List(_bufferFrames);
  }

  final int sampleRate;

  /// Taille d'une trame d'analyse, en échantillons. 256 @ 44,1 kHz = 5,8 ms.
  final int hopSize;

  /// Durée de son gardée en mémoire pour l'analyse.
  final double bufferSeconds;

  /// Plage de tempo cherchée. Modifiable à chaud : n'affecte que [estimate].
  double minBpm;
  double maxBpm;

  /// A priori de tempo. Quand il est actif, les candidats hors de la bande
  /// [priorLowBpm, priorHighBpm] sont pénalisés d'autant plus qu'ils s'en
  /// éloignent (en octaves). C'est ce qui permet de trancher entre 125 et
  /// 250 sur de la house : l'autocorrélation seule ne le peut pas, les
  /// deux sont "vrais". À désactiver quand l'utilisateur impose une plage.
  ///
  /// L'a priori est asymétrique : doux vers le bas (les sous-multiples
  /// sont déjà avantagés par le score, pas besoin d'en rajouter), plus
  /// ferme vers le haut (c'est là que les subdivisions — croches de basse,
  /// charleys — font croire à un tempo double).
  bool usePrior = true;
  double priorLowBpm = 90;
  double priorHighBpm = 180;
  double priorSigmaLowOctaves = 0.5;
  double priorSigmaHighOctaves = 0.35;

  /// Poids de l'a priori pour un tempo donné (1 dans la bande, < 1 dehors).
  double priorWeight(double bpm) {
    if (!usePrior) return 1;
    double z;
    if (bpm < priorLowBpm) {
      z = log(priorLowBpm / bpm) / ln2 / priorSigmaLowOctaves;
    } else if (bpm > priorHighBpm) {
      z = log(bpm / priorHighBpm) / ln2 / priorSigmaHighOctaves;
    } else {
      return 1;
    }
    return exp(-0.5 * z * z);
  }

  final int _bufferFrames;
  final double _lpAlpha;

  /// Nombre de trames par seconde.
  double get framesPerSecond => sampleRate / hopSize;

  /// Durée de son actuellement en mémoire, en secondes.
  double get bufferedSeconds => _filled / framesPerSecond;

  // --- état du pipeline ---------------------------------------------------

  // Sortie du passe-bas.
  double _lp = 0;

  // Trame en cours de remplissage.
  double _frameEnergy = 0;
  int _frameCount = 0;

  // RMS de la trame précédente (pour le flux).
  double _prevLogRms = log(_rmsFloor);

  // Buffer circulaire du flux d'onsets : une valeur par trame.
  late final Float64List _onsets;
  int _writePos = 0;
  int _filled = 0;

  // Plancher ajouté au RMS avant le log : évite que le bruit de fond quasi
  // nul produise des variations de log énormes. 0.01 = -40 dBFS.
  static const double _rmsFloor = 0.01;

  // Fraction du meilleur score qu'un pic plus rapide doit atteindre pour
  // être préféré. Trop haut → on retombe sur les sous-multiples (÷2, ÷3) ;
  // trop bas → on saute sur les subdivisions (×2).
  static const double _keepRatio = 0.5;

  /// Vide toute la mémoire (changement de morceau, redémarrage).
  void reset() {
    _lp = 0;
    _frameEnergy = 0;
    _frameCount = 0;
    _prevLogRms = log(_rmsFloor);
    _writePos = 0;
    _filled = 0;
  }

  /// Pousse des échantillons PCM 16 bits mono.
  void addSamples(Int16List samples) {
    for (final s in samples) {
      // 1. Normaliser en -1..1 et passer en passe-bas : on ne garde que
      //    les basses (kick, basse), là où le tempo est le plus net.
      final x = s / 32768.0;
      _lp += _lpAlpha * (x - _lp);

      // 2. Accumuler l'énergie de la trame.
      _frameEnergy += _lp * _lp;
      _frameCount++;

      if (_frameCount == hopSize) {
        _endFrame();
      }
    }
  }

  void _endFrame() {
    // 3. RMS de la trame, en log (compresse la dynamique : un passage
    //    doux et un passage fort donnent des onsets comparables).
    final rms = sqrt(_frameEnergy / hopSize);
    final logRms = log(rms + _rmsFloor);

    // 4. Flux d'onset = montée d'énergie par rapport à la trame précédente.
    //    On ignore les descentes (max 0) : seule l'attaque nous intéresse.
    final flux = max(0.0, logRms - _prevLogRms);
    _prevLogRms = logRms;

    // 5. Ranger dans le buffer circulaire.
    _onsets[_writePos] = flux;
    _writePos = (_writePos + 1) % _bufferFrames;
    if (_filled < _bufferFrames) _filled++;

    _frameEnergy = 0;
    _frameCount = 0;
  }

  /// Vrai si [ratio] vaut 1,5, 2, 3 ou 4 à 5 % près.
  static bool _isIntegerRatio(double ratio) {
    for (final k in [1.5, 2, 3, 4]) {
      if ((ratio / k - 1).abs() < 0.05) return true;
    }
    return false;
  }

  /// Estime le tempo à partir du son en mémoire.
  /// Retourne null s'il n'y a pas encore assez de son (< 3 s) ou pas de
  /// périodicité exploitable.
  BpmResult? estimate() {
    final n = _filled;
    if (n < 3 * framesPerSecond) return null;

    // Copie du buffer circulaire dans l'ordre chronologique, centrée
    // (moyenne retirée) : sinon l'autocorrélation est dominée par la
    // composante continue et tous les lags se ressemblent.
    final raw = Float64List(n);
    final start = (_writePos - n + _bufferFrames) % _bufferFrames;
    for (var i = 0; i < n; i++) {
      raw[i] = _onsets[(start + i) % _bufferFrames];
    }

    // Lissage par un noyau triangulaire sur 5 trames (~30 ms). Les onsets
    // bruts sont des pics d'une trame : quand la période n'est pas un
    // nombre entier de trames, l'autocorrélation tombe "à côté" et peut
    // préférer un multiple de la période qui tombe mieux par hasard.
    // Élargir les pics rend l'analyse insensible à ce demi-décalage.
    const kernel = [1.0, 2.0, 3.0, 2.0, 1.0];
    const kernelSum = 9.0;
    final x = Float64List(n);
    double mean = 0;
    for (var i = 0; i < n; i++) {
      double acc = 0;
      for (var k = 0; k < kernel.length; k++) {
        final j = i + k - 2;
        if (j >= 0 && j < n) acc += kernel[k] * raw[j];
      }
      x[i] = acc / kernelSum;
      mean += x[i];
    }
    mean /= n;
    double energy = 0;
    for (var i = 0; i < n; i++) {
      x[i] -= mean;
      energy += x[i] * x[i];
    }
    if (energy <= 0) return null;

    // Lags correspondant à la plage de tempo : lag = trames par temps.
    final lagMin = max(2, (framesPerSecond * 60 / maxBpm).floor());
    final lagMax = min(n ~/ 2 - 1, (framesPerSecond * 60 / minBpm).ceil());
    if (lagMax <= lagMin + 1) return null;

    // Autocorrélation normalisée : r[L] = à quel point le signal décalé de
    // L trames ressemble à lui-même. 1 = identique, 0 = aucun rapport.
    // On la calcule jusqu'à 3 × lagMax pour le score harmonique.
    final maxLag = min(3 * lagMax + 1, n - 1);
    final r = Float64List(maxLag + 1);
    final norm = energy / n;
    for (var lag = 1; lag <= maxLag; lag++) {
      double sum = 0;
      for (var t = 0; t + lag < n; t++) {
        sum += x[t] * x[t + lag];
      }
      r[lag] = sum / (n - lag) / norm;
    }

    // Score harmonique : un vrai tempo a aussi des pics à 2× et 3× sa
    // période. Ça favorise le tempo "fondamental" par rapport aux pics
    // parasites. Le score reste dominé par r[L] lui-même.
    //
    // Les multiples d'un lag entier ne tombent pas pile sur les multiples
    // de la vraie période (34,45 × 2 = 68,9, pas 68) : on prend donc le
    // max de r dans un petit voisinage autour de 2L et 3L.
    double peakNear(int center, int radius) {
      var best = 0.0;
      for (var l = center - radius; l <= center + radius; l++) {
        if (l >= 1 && l <= maxLag && r[l] > best) best = r[l];
      }
      return best;
    }

    double score(int lag) {
      var s = r[lag];
      if (2 * lag <= maxLag) s += 0.5 * peakNear(2 * lag, 1);
      if (3 * lag <= maxLag) s += 0.33 * peakNear(3 * lag, 2);
      return s;
    }

    // Recherche des maxima locaux dans la plage. Chaque pic porte son
    // score brut et son score pondéré par l'a priori.
    final peaks = <(int, double, double)>[];
    for (var lag = lagMin; lag <= lagMax; lag++) {
      if (r[lag] <= 0) continue;
      final s = score(lag);
      if (s > score(lag - 1) && s >= score(lag + 1)) {
        final w = priorWeight(60 * framesPerSecond / lag);
        peaks.add((lag, s, s * w));
      }
    }
    if (peaks.isEmpty) return null;
    peaks.sort((a, b) => b.$3.compareTo(a.$3));

    // Choix du tempo : la périodicité LA PLUS RAPIDE qui reste forte,
    // PARMI LES SUBDIVISIONS ENTIÈRES du meilleur pic.
    //
    // En musique réelle, le motif se répète par mesure : la corrélation à
    // 2, 3 ou 4 temps est donc toujours au moins aussi bonne qu'à 1 temps,
    // et les sous-multiples du tempo (÷2, ÷3) gagnent structurellement au
    // score brut. À l'inverse, un sur-multiple (×2) n'est fort que s'il y
    // a de vraies subdivisions (et l'a priori le pénalise). Donc : parmi
    // les pics dont le score pondéré atteint au moins [_keepRatio] du
    // meilleur ET dont la période est en rapport simple avec celle du
    // meilleur (1,5, 2, 3 ou 4), on garde le plus rapide. Cette contrainte
    // évite de sauter sur une croche pointée (rapport 4/3), périodicité
    // réelle mais qui n'est pas le tempo. Le rapport 1,5 est admis : c'est
    // la relation entre le "÷3" et le "÷2" d'un même tempo.
    final top = peaks.first;
    final threshold = top.$3 * _keepRatio;
    var best = top;
    for (final p in peaks) {
      if (p.$3 < threshold || p.$1 >= best.$1) continue;
      if (_isIntegerRatio(top.$1 / p.$1)) best = p;
    }

    // Interpolation parabolique : on ajuste une parabole sur les trois
    // points autour du pic pour trouver le sommet entre deux lags entiers.
    final lag = best.$1;
    final y0 = score(lag - 1), y1 = score(lag), y2 = score(lag + 1);
    final denom = y0 - 2 * y1 + y2;
    final delta = denom == 0 ? 0.0 : (0.5 * (y0 - y2) / denom).clamp(-1, 1);
    final lagFrac = lag + delta;

    final bpm = 60 * framesPerSecond / lagFrac;

    // Phase du beat : on replie le flux d'onsets modulo la période (comme
    // si on empilait toutes les mesures) dans 32 cases ; la case la plus
    // chargée est la position du temps. On ne garde que les 4 dernières
    // secondes, pondérées vers le récent, pour suivre les dérives.
    const bins = 32;
    final hist = Float64List(bins);
    final from = max(0, n - (4 * framesPerSecond).round());
    for (var i = from; i < n; i++) {
      final phase = (i / lagFrac) % 1.0;
      final weight = (i - from) / (n - from); // 0 → 1, récent = lourd
      hist[(phase * bins).floor() % bins] += max(0.0, x[i]) * weight;
    }
    var bestBin = 0;
    for (var b = 1; b < bins; b++) {
      if (hist[b] > hist[bestBin]) bestBin = b;
    }
    final beatPhase = (bestBin + 0.5) / bins;
    final lastPhase = ((n - 1) / lagFrac) % 1.0;
    final framesToNextBeat = ((beatPhase - lastPhase) % 1.0) * lagFrac;

    final candidates = peaks
        .take(5)
        .map((p) => BpmCandidate(60 * framesPerSecond / p.$1, p.$3))
        .toList();

    return BpmResult(
      bpm: bpm,
      confidence: r[lag].clamp(0.0, 1.0),
      candidates: candidates,
      periodSeconds: lagFrac / framesPerSecond,
      secondsToNextBeat: framesToNextBeat / framesPerSecond,
    );
  }
}
