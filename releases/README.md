# Versions installables

Les APK sont publiés sur GitHub :
https://github.com/Blanka-sf4/tomatozor/releases

- `TOMATOZOR-1.1.0.apk` — 11 septembre 2026, signé avec la clé TOMATOZOR.
  Mode micro, mode de secours (tap), mode métronome, historique avec extraits
  audio et partage, personnages vivants, cris par tranche de tempo.
- `tomatozor-pastelle-edition-v1.apk` — première version (clé de debug :
  ne peut pas être mise à jour par-dessus, désinstaller avant).

Les fichiers .apk restent dans ce dossier sur le disque mais ne sont plus
versionnés dans git (trop gros) : c'est GitHub Releases qui les héberge.

Publier une nouvelle version :
    1. version: X.Y.Z+N dans pubspec.yaml (N doit augmenter)
    2. flutter build apk --release
    3. cp build/app/outputs/flutter-apk/app-release.apk releases/TOMATOZOR-X.Y.Z.apk
    4. gh release create vX.Y.Z releases/TOMATOZOR-X.Y.Z.apk --title "TOMATOZOR X.Y.Z" --notes "..."
