# Versions installables

- `tomatozor-pastelle-edition-v1.apk` — 11 septembre 2026. Version validée
  "parfaite" : mode normal (micro) + mode de secours (tap), icône plein cadre,
  cheval / cochon, fond kawaii / braises.

Installation sans PC : envoyer le fichier sur le téléphone (mail, Drive…),
l'ouvrir, accepter "installer depuis cette source".

Installation avec câble :
    adb install -r releases/tomatozor-pastelle-edition-v1.apk

Regénérer après modification :
    flutter build apk --release
    cp build/app/outputs/flutter-apk/app-release.apk releases/<nom>.apk
