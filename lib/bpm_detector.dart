import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

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
///   échantillons → FFT glissante (2048 pts, Hann, tous les 256)
///   → flux spectral (somme des montées de log-magnitude, bin par bin)
///   → autocorrélation → pic → interpolation → BPM
///
/// Le flux spectral compte les attaques dans chaque bin de fréquence
/// indépendamment : une nouvelle note de basse, une syllabe, un accord y
/// laissent une trace, là où une simple mesure d'énergie ne voit que les
/// gros coups de batterie. C'est ce qui rend le hip-hop et les morceaux
/// sans batterie franche détectables.
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
    this.fftSize = 2048,
    double lowZoneHz = 300,
    double midZoneHz = 3000,
  }) : _bufferFrames = (bufferSeconds * sampleRate / hopSize).round(),
       _fft = FFT(fftSize),
       _window = Float64List(fftSize),
       _ring = Float64List(fftSize),
       _lowBins = (lowZoneHz * fftSize / sampleRate).round(),
       _midBins = (midZoneHz * fftSize / sampleRate).round() {
    _onsets = Float64List(_bufferFrames);
    _onsetsMid = Float64List(_bufferFrames);
    _onsetsKick = Float64List(_bufferFrames);
    _prevLogMag = Float64List(fftSize ~/ 2 + 1);
    _frame = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      _window[i] = 0.5 - 0.5 * cos(2 * pi * i / fftSize); // Hann
    }
  }

  /// Taille de la FFT (fenêtre d'analyse). 2048 @ 44,1 kHz = 46 ms.
  final int fftSize;

  /// Poids des zones (basse < 300 Hz, médium 300-3000, aiguë > 3 kHz) dans
  /// le flux principal, chaque zone étant d'abord moyennée par bin.
  double zoneWeightLow = 1.0;
  double zoneWeightMid = 0.8;
  double zoneWeightHigh = 0.5;

  final int sampleRate;

  /// Taille d'une trame d'analyse, en échantillons. 256 @ 44,1 kHz = 5,8 ms.
  final int hopSize;

  /// Durée de son gardée en mémoire pour l'analyse.
  final double bufferSeconds;

  /// Trace de debug des candidats (tests).
  bool debugTrace = false;

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
  final FFT _fft;
  final Float64List _window;
  // Les derniers [fftSize] échantillons (anneau) et la trame de travail.
  final Float64List _ring;
  int _ringPos = 0;
  late final Float64List _frame;
  // Bins de fréquence délimitant les zones basse / médium / aiguë.
  final int _lowBins;
  final int _midBins;
  // Log-magnitude de la trame précédente, pour le flux.
  late Float64List _prevLogMag;

  /// Nombre de trames par seconde.
  double get framesPerSecond => sampleRate / hopSize;

  /// Durée de son actuellement en mémoire, en secondes.
  double get bufferedSeconds => _filled / framesPerSecond;

  // --- état du pipeline ---------------------------------------------------

  // Échantillons reçus depuis la dernière trame.
  int _frameCount = 0;

  // Buffers circulaires du flux d'onsets : une valeur par trame. Le
  // premier combine kick + caisse claire ; le second ne garde que la
  // caisse claire, pour repérer le backbeat.
  late final Float64List _onsets;
  late final Float64List _onsetsMid;
  // Bande "kick propre" (< 100 Hz, deux pôles), uniquement pour le test de
  // coïncidence kick / caisse claire.
  late final Float64List _onsetsKick;
  int _writePos = 0;
  int _filled = 0;

  // Fraction du meilleur score qu'un pic plus rapide doit atteindre pour
  // être préféré. Trop haut → on retombe sur les sous-multiples (÷2, ÷3) ;
  // trop bas → on saute sur les subdivisions (×2).
  static const double _keepRatio = 0.5;

  /// Corrélation brute minimale d'un candidat plus rapide, relative à celle
  /// du meilleur, pour être préféré.
  static const double _rawRatioMin = 0.5;

  /// Contraste backbeat minimal (r_mid(2L) − r_mid(L)) pour qu'un candidat
  /// soit retenu par la règle du backbeat plutôt que par la règle générale.
  static const double _backbeatMinContrast = 0.2;

  /// Score pondéré minimal du meilleur pic pour appliquer la règle du
  /// backbeat (en dessous, le signal est trop faible pour raffiner).
  static const double _backbeatMinTopScore = 0.25;

  /// Vrai si [ratio] vaut 1,5, 2, 3 ou 4 à 5 % près.
  static bool _isIntegerRatio(double ratio) {
    for (final k in [1.5, 2, 3, 4]) {
      if ((ratio / k - 1).abs() < 0.05) return true;
    }
    return false;
  }

  /// Vide toute la mémoire (changement de morceau, redémarrage).
  void reset() {
    _ring.fillRange(0, _ring.length, 0);
    _ringPos = 0;
    _frameCount = 0;
    _prevLogMag.fillRange(0, _prevLogMag.length, 0);
    _writePos = 0;
    _filled = 0;
  }

  /// Pousse des échantillons PCM 16 bits mono.
  void addSamples(Int16List samples) {
    for (final s in samples) {
      _ring[_ringPos] = s / 32768.0;
      _ringPos = (_ringPos + 1) % fftSize;
      _frameCount++;
      if (_frameCount == hopSize) {
        _endFrame();
      }
    }
  }

  void _endFrame() {
    _frameCount = 0;
    // 1. Fenêtre de Hann sur les derniers fftSize échantillons.
    for (var i = 0; i < fftSize; i++) {
      _frame[i] = _ring[(_ringPos + i) % fftSize] * _window[i];
    }
    // 2. FFT → log-magnitude par bin. Le ×50 place le coude du log au bon
    //    endroit pour un signal micro normalisé en -1..1.
    final spec = _fft.realFft(_frame).discardConjugates();
    final nBins = spec.length;
    // 3. Flux spectral = somme des montées de log-magnitude, bin par bin,
    //    par zone : basse (< 300 Hz : kick, basse), médium (300-3000 Hz :
    //    caisse claire, voix, accords), aiguë (> 3 kHz : charleys).
    double low = 0, mid = 0, high = 0;
    for (var b = 0; b < nBins; b++) {
      final c = spec[b];
      final mag = sqrt(c.x * c.x + c.y * c.y);
      final lm = log(1 + mag * 50);
      final d = lm - _prevLogMag[b];
      _prevLogMag[b] = lm;
      if (d <= 0) continue;
      if (b < _lowBins) {
        low += d;
      } else if (b < _midBins) {
        mid += d;
      } else {
        high += d;
      }
    }
    // 4. Chaque zone est ramenée à une moyenne par bin (sinon les aigus,
    //    qui ont 60 fois plus de bins que les basses, écrasent tout), puis
    //    pondérée : le kick et la basse pilotent, les charleys sont un
    //    appoint. Les zones basse et médium servent aussi au backbeat.
    low /= _lowBins;
    mid /= (_midBins - _lowBins);
    high /= (nBins - _midBins);
    _onsets[_writePos] =
        zoneWeightLow * low + zoneWeightMid * mid + zoneWeightHigh * high;
    _onsetsMid[_writePos] = mid;
    _onsetsKick[_writePos] = low;
    _writePos = (_writePos + 1) % _bufferFrames;
    if (_filled < _bufferFrames) _filled++;
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
    final rawMid = Float64List(n);
    final rawKick = Float64List(n);
    final start = (_writePos - n + _bufferFrames) % _bufferFrames;
    for (var i = 0; i < n; i++) {
      raw[i] = _onsets[(start + i) % _bufferFrames];
      rawMid[i] = _onsetsMid[(start + i) % _bufferFrames];
      rawKick[i] = _onsetsKick[(start + i) % _bufferFrames];
    }

    // Lissage par un noyau triangulaire sur 5 trames (~30 ms). Les onsets
    // bruts sont des pics d'une trame : quand la période n'est pas un
    // nombre entier de trames, l'autocorrélation tombe "à côté" et peut
    // préférer un multiple de la période qui tombe mieux par hasard.
    // Élargir les pics rend l'analyse insensible à ce demi-décalage.
    const kernel = [1.0, 2.0, 3.0, 2.0, 1.0];
    const kernelSum = 9.0;
    final x = Float64List(n);
    final xMid = Float64List(n);
    final xLow = Float64List(n); // bande kick propre (< 100 Hz)
    double mean = 0, meanMid = 0;
    for (var i = 0; i < n; i++) {
      double acc = 0, accMid = 0, accKick = 0;
      for (var k = 0; k < kernel.length; k++) {
        final j = i + k - 2;
        if (j >= 0 && j < n) {
          acc += kernel[k] * raw[j];
          accMid += kernel[k] * rawMid[j];
          accKick += kernel[k] * rawKick[j];
        }
      }
      x[i] = acc / kernelSum;
      xMid[i] = accMid / kernelSum;
      xLow[i] = accKick / kernelSum;
      mean += x[i];
      meanMid += xMid[i];
    }
    mean /= n;
    meanMid /= n;
    double meanKick = 0;
    for (var i = 0; i < n; i++) {
      meanKick += xLow[i];
    }
    meanKick /= n;
    double energy = 0, energyMid = 0, energyKick = 0;
    for (var i = 0; i < n; i++) {
      x[i] -= mean;
      xMid[i] -= meanMid;
      xLow[i] -= meanKick;
      energy += x[i] * x[i];
      energyMid += xMid[i] * xMid[i];
      energyKick += xLow[i] * xLow[i];
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
    final rMid = Float64List(maxLag + 1);
    final rKick = Float64List(maxLag + 1);
    final norm = energy / n;
    final normMid = energyMid > 0 ? energyMid / n : 1.0;
    final normKick = energyKick > 0 ? energyKick / n : 1.0;
    for (var lag = 1; lag <= maxLag; lag++) {
      double sum = 0, sumMid = 0, sumKick = 0;
      for (var t = 0; t + lag < n; t++) {
        sum += x[t] * x[t + lag];
        sumMid += xMid[t] * xMid[t + lag];
        sumKick += xLow[t] * xLow[t + lag];
      }
      r[lag] = sum / (n - lag) / norm;
      rMid[lag] = energyMid > 0 ? sumMid / (n - lag) / normMid : 0.0;
      rKick[lag] = energyKick > 0 ? sumKick / (n - lag) / normKick : 0.0;
    }

    /// Contraste "un temps sur deux" d'une bande pour un candidat de
    /// période [lag] : r(2L) − r(L), avec un voisinage pour l'arrondi.
    double contrast(Float64List rr, int lag) {
      if (2 * lag + 1 > maxLag) return 0;
      double near(int c, int rad) {
        var best = -1.0;
        for (var l = c - rad; l <= c + rad; l++) {
          if (l >= 1 && l <= maxLag && rr[l] > best) best = rr[l];
        }
        return best;
      }

      return near(2 * lag, 1) - near(lag, 1);
    }

    /// Preuve de backbeat d'un candidat : l'asymétrie de la bande caisse
    /// claire MOINS celle de la bande kick. Si le kick montre la même
    /// asymétrie, c'est son clic qu'on entend dans les médiums, pas une
    /// caisse claire (un morceau kick seul passerait sinon pour un backbeat
    /// au double du tempo).
    double backbeatEvidence(int lag) =>
        contrast(rMid, lag) - max(0.0, contrast(rKick, lag));

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

    // Backbeat : la caisse claire sur 2 et 4 tombe UN temps sur deux. Pour
    // un candidat de période L (un temps), la bande caisse claire seule a
    // donc une corrélation forte à 2L et faible à L : le contraste
    // r_mid(2L) − r_mid(L) est nettement positif pour le vrai tempo, et
    // proche de zéro pour son double (2L devient L) comme pour sa moitié
    // (L et 2L y sont tous deux des multiples de la période caisse claire).
    // Ça vaut pour le hip-hop à 75, la house à 125 et la DnB à 172. Sans
    // caisse claire (clics, kick seul, speedcore), tous les contrastes sont
    // ~0 et on suit la règle générale.
    final top = peaks.first;
    // La règle ne s'applique qu'à des candidats sérieux : au moins la
    // moitié du meilleur score, et un meilleur score qui n'est pas du
    // bruit. Sinon, sur un signal faible, elle piocherait n'importe quoi.
    (int, double, double)? backbeatPick;
    var bestBb = _backbeatMinContrast;
    for (final p in peaks) {
      if (top.$3 < _backbeatMinTopScore || p.$3 < top.$3 * 0.5) continue;
      final bb = backbeatEvidence(p.$1);
      if (debugTrace) {
        // ignore: avoid_print
        print(
          '  cand ${(60 * framesPerSecond / p.$1).toStringAsFixed(1)} '
          'score ${p.$3.toStringAsFixed(2)} '
          'mid ${contrast(rMid, p.$1).toStringAsFixed(2)} '
          'kick ${contrast(rKick, p.$1).toStringAsFixed(2)} '
          'preuve ${bb.toStringAsFixed(2)}',
        );
      }
      if (bb > bestBb) {
        bestBb = bb;
        backbeatPick = p;
      }
    }

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
    // Le saut vers un candidat plus rapide se juge sur les scores SANS
    // l'a priori (deux clics purs à 200 et 100 ont des scores identiques,
    // le petit malus au-dessus de 180 ne doit pas trancher seul), avec une
    // barre fixe. On a essayé de la rendre plus exigeante quand le lent est
    // plausible, pour le rap à 90-100 : ça casse le hardcore à 195, dont
    // les chiffres sont indiscernables de ceux du rap (97/195 vs 99/199).
    // Le rap, c'est le preset 60-120.
    final threshold = top.$2 * _keepRatio;
    var best = top;
    if (backbeatPick != null) {
      best = backbeatPick;
    } else {
      for (final p in peaks) {
        if (p.$2 < threshold || p.$1 >= best.$1) continue;
        // Un candidat rapide franchement improbable (a priori < 0,5, soit
        // au-delà de ~245 BPM en Auto) ne peut pas gagner par ce biais.
        if (priorWeight(60 * framesPerSecond / p.$1) < 0.5) continue;
        // Le score harmonique d'un candidat au double hérite de la moitié
        // du score du vrai tempo (terme 2L) : il faut aussi que sa propre
        // corrélation brute tienne la route, sinon des charleys discrets
        // suffiraient à doubler le tempo.
        if (r[p.$1] < _rawRatioMin * r[top.$1]) continue;
        if (_isIntegerRatio(top.$1 / p.$1)) best = p;
      }
    }

    // Figures pointées : un rival presque aussi fort (≥ 80 %) en rapport
    // 4:3 ou 3:2 avec le choix courant est une croche pointée (4/3 du
    // tempo, typique des delays de psytrance : 186 pour 140) ou une noire
    // pointée (2/3 du tempo : 92 pour 138). Le vrai temps est le non-pointé :
    // le plus LENT des deux en 4:3, le plus RAPIDE en 3:2.
    for (final p in peaks) {
      if (p == best || p.$3 < 0.8 * best.$3) continue;
      final ratio = p.$1 / best.$1; // > 1 : p est plus lent que best
      if ((ratio / (4 / 3) - 1).abs() < 0.05) {
        best = p; // best était la croche pointée de p
      } else if ((ratio / (2 / 3) - 1).abs() < 0.05) {
        best = p; // best était la noire pointée de p
      }
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
