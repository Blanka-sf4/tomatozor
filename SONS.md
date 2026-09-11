# Les sons de TOMATOZOR

Tout est synthétisé par des scripts Python (numpy), aucun sample externe.
Pour régénérer un son : `python3 tools/<script>.py` puis rebuild.

| Fichier                    | Script                 | Quand                          | Statut            |
|----------------------------|------------------------|--------------------------------|-------------------|
| `assets/sounds/sneeze.wav` | `tools/make_sneeze.py` | Calage en mode normal (micro)  | Validé "parfait"  |
| `assets/sounds/oink.wav`   | `tools/make_oink.py`   | Calage en mode secours (tap)   | Validé "parfait"  |

## sneeze.wav — hennissement de cheval (1,85 s)
Malgré son nom (c'était un éternuement à l'origine), c'est un hennissement :
- note aiguë qui monte brièvement (950 → 1250 Hz) puis descend jusqu'à 420 Hz
- trille à ~21 Hz (le "hi-hi-hi"), en hauteur (±7 %) et en volume
- formants "cuivrés" à 900 / 1700 / 2900 Hz
- ébrouement de naseaux à la fin (0,45 s, modulation 26 Hz)
Paramètres à toucher : `f_start, f_peak, f_end`, `trill_rate`, `DUR`.

## oink.wav — cochon (1,66 s)
Quatre grognements graves, sans couinement (le couinement aigu a été essayé
et refusé) : trois courts (0,24 / 0,22 / 0,26 s) + un long traînant (0,55 s).
- hauteur en cloche 170 → 260 Hz, trémolo 35 Hz
- "rauque" : bruit modulé par la voix (le râpeux du groin)
- formants nasaux 480 / 950 / 1900 Hz (ce qui fait "groin" et pas "meuh")
La fonction `squeal()` (couinement) existe toujours dans le script, inutilisée.
Paramètres : la liste `parts` (nombre et durée des grognements), `grunt()`.

## Remplacer par un vrai sample
Déposer un WAV au même nom dans `assets/sounds/`. Si MP3 : changer l'extension
dans `pubspec.yaml` (section assets) et dans `_celebrate()` de `lib/main.dart`.
Freesound.org, licence CC0, "horse neigh" / "pig oink".

## Où ça se joue
`lib/main.dart`, méthode `_celebrate()` : choisit le fichier selon `_mode`,
joue via `audioplayers` (volume 0,7, sans couper la musique en cours).
