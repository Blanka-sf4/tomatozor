import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Un calage enregistré : son BPM, l'heure, et l'extrait audio.
class HistoryEntry {
  HistoryEntry({required this.bpm, required this.at, required this.file});

  final double bpm;
  final DateTime at;

  /// Chemin du WAV (8 s de son analysé), dans le dossier privé de l'appli.
  final String file;

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'at': at.toIso8601String(),
    'file': file,
  };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
    bpm: (j['bpm'] as num).toDouble(),
    at: DateTime.parse(j['at'] as String),
    file: j['file'] as String,
  );
}

/// Stockage persistant : les 5 derniers calages au micro (avec leur son)
/// et le dernier BPM tapé en mode secours. Tout est dans le dossier
/// privé de l'appli : invisible pour les autres applis, supprimé avec elle.
class HistoryStore {
  static const int maxEntries = 5;

  final List<HistoryEntry> entries = [];
  double? lastTapBpm;

  /// Décalage du point de beat, en ms (positif = plus tôt). Réglable dans
  /// Options ; la valeur par défaut compense la latence micro typique.
  static const int defaultLatencyMs = 60;
  int latencyMs = defaultLatencyMs;

  /// Dernier tempo réglé dans le mode métronome, et son son.
  double metroBpm = 120;
  String metroSound = 'wood';

  /// Mesure du métronome : temps par mesure (0 = pas de temps fort).
  int metroBeatsPerBar = 4;

  /// Ambiance : lumières (néons, flashs), sons (cris, squish…), vibrations,
  /// et vibration sur chaque temps du métronome.
  bool lightsOn = true;
  bool soundsOn = true;
  bool vibrationOn = true;
  bool metroVibrate = false;

  /// Le tutoriel a-t-il été vu ?
  bool tutorialSeen = false;

  /// Le preset caché « 1-9999 » (mode fou) est-il débloqué ?
  bool crazyUnlocked = false;

  Directory? _dir;

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    // Dossier "externe" de l'appli (Android/data/<pkg>/files) : toujours
    // privé et supprimé avec l'appli, mais lisible par adb — pratique pour
    // récupérer les extraits et calibrer le détecteur sur de vrais sons.
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/history');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    return _dir!;
  }

  Future<File> _indexFile() async =>
      File('${(await _directory()).path}/index.json');

  Future<void> load() async {
    final f = await _indexFile();
    if (!await f.exists()) return;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      entries
        ..clear()
        ..addAll(
          (j['entries'] as List)
              .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
              // On ignore une entrée dont le fichier aurait disparu.
              .where((e) => File(e.file).existsSync()),
        );
      lastTapBpm = (j['lastTapBpm'] as num?)?.toDouble();
      latencyMs = (j['latencyMs'] as num?)?.toInt() ?? defaultLatencyMs;
      metroBpm = (j['metroBpm'] as num?)?.toDouble() ?? 120;
      metroSound = (j['metroSound'] as String?) ?? 'wood';
      metroBeatsPerBar = (j['metroBeatsPerBar'] as num?)?.toInt() ?? 4;
      lightsOn = (j['lightsOn'] as bool?) ?? true;
      soundsOn = (j['soundsOn'] as bool?) ?? true;
      vibrationOn = (j['vibrationOn'] as bool?) ?? true;
      metroVibrate = (j['metroVibrate'] as bool?) ?? false;
      tutorialSeen = (j['tutorialSeen'] as bool?) ?? false;
      crazyUnlocked = (j['crazyUnlocked'] as bool?) ?? false;
    } catch (_) {
      // Index illisible : on repart de zéro plutôt que de planter.
      entries.clear();
      lastTapBpm = null;
    }
  }

  Future<void> _save() async {
    final f = await _indexFile();
    await f.writeAsString(
      jsonEncode({
        'entries': entries.map((e) => e.toJson()).toList(),
        'lastTapBpm': lastTapBpm,
        'latencyMs': latencyMs,
        'metroBpm': metroBpm,
        'metroSound': metroSound,
        'metroBeatsPerBar': metroBeatsPerBar,
        'lightsOn': lightsOn,
        'soundsOn': soundsOn,
        'vibrationOn': vibrationOn,
        'metroVibrate': metroVibrate,
        'tutorialSeen': tutorialSeen,
        'crazyUnlocked': crazyUnlocked,
      }),
    );
  }

  /// Ajoute un calage avec son extrait audio (PCM 16 bits mono).
  Future<void> add(double bpm, Int16List pcm, int sampleRate) async {
    final dir = await _directory();
    final at = DateTime.now();
    final file = File('${dir.path}/clip_${at.millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(encodeWav(pcm, sampleRate));
    entries.insert(0, HistoryEntry(bpm: bpm, at: at, file: file.path));
    while (entries.length > maxEntries) {
      final old = entries.removeLast();
      final f = File(old.file);
      if (await f.exists()) await f.delete();
    }
    await _save();
  }

  Future<void> remove(HistoryEntry entry) async {
    entries.remove(entry);
    final f = File(entry.file);
    if (await f.exists()) await f.delete();
    await _save();
  }

  Future<void> setAmbiance({
    bool? lights,
    bool? sounds,
    bool? vibration,
    bool? metroVibrate,
  }) async {
    if (lights != null) lightsOn = lights;
    if (sounds != null) soundsOn = sounds;
    if (vibration != null) vibrationOn = vibration;
    if (metroVibrate != null) this.metroVibrate = metroVibrate;
    await _save();
  }

  Future<void> setMetroBeatsPerBar(int n) async {
    metroBeatsPerBar = n;
    await _save();
  }

  Future<void> setCrazyUnlocked() async {
    crazyUnlocked = true;
    await _save();
  }

  Future<void> setTutorialSeen() async {
    tutorialSeen = true;
    await _save();
  }

  Future<void> setMetroSound(String sound) async {
    metroSound = sound;
    await _save();
  }

  Future<void> setMetroBpm(double bpm) async {
    metroBpm = bpm;
    await _save();
  }

  Future<void> setLatencyMs(int ms) async {
    latencyMs = ms;
    await _save();
  }

  Future<void> setLastTapBpm(double bpm) async {
    lastTapBpm = bpm;
    await _save();
  }
}

/// Fabrique un fichier WAV (en-tête RIFF + PCM 16 bits mono little-endian).
Uint8List encodeWav(Int16List pcm, int sampleRate) {
  final dataBytes = pcm.lengthInBytes;
  final out = ByteData(44 + dataBytes);
  void str(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // taille du bloc fmt
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little); // octets / seconde
  out.setUint16(32, 2, Endian.little); // octets par échantillon
  out.setUint16(34, 16, Endian.little); // bits
  str(36, 'data');
  out.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    out.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return out.buffer.asUint8List();
}
