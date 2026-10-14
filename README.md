# La Fourchette — version de test Android

Application d'estimation par fourchettes : on encadre une valeur, plus c'est serré, plus ça rapporte, et hors fourchette c'est 0 point. Cette version contient **1 017 questions** réparties en 8 thèmes, des parties aléatoires ou par thème, un chrono de 20 s, la réponse exacte (150 points), un classement « niveau » et « cumulé », et deux ambiances (Vif / Chaleureuse).

> **L'APK n'est pas inclus.** Il n'a pas pu être compilé dans l'environnement où ce projet a été écrit (pas d'accès au SDK Android). Le projet ci-dessous est prêt à être compilé par l'une des trois voies. La compilation n'a donc **pas été testée de bout en bout** ; la page web, elle, a été testée dans un navigateur (parties simulées, sauvegarde, réponse exacte).

## Voie 1 — GitHub Actions (la plus simple, rien à installer)

1. Créez un dépôt GitHub (privé convient) et envoyez-y tout le contenu de ce dossier.
2. Onglet **Actions** → « Build APK de test » → **Run workflow** (il se lance aussi à chaque envoi sur `main`).
3. Au bout de quelques minutes, téléchargez l'artefact **la-fourchette-test-apk** : il contient `app-debug.apk`.

## Voie 2 — En local

Prérequis : Node 20+, Java 21, Android SDK (variable `ANDROID_HOME`), Python 3.

```bash
./build-apk.sh
# APK : android/app/build/outputs/apk/debug/app-debug.apk
```

## Voie 3 — Android Studio

```bash
python3 build_questions.py && python3 build_app.py
npm install
npx cap add android
npx cap sync android
npx cap open android      # puis Build > Build APK(s)
```

## Installer sur un téléphone

Copiez `app-debug.apk` sur le téléphone, ouvrez-le et autorisez l'installation depuis cette source. Ou, avec un câble : `adb install app-debug.apk`. C'est un APK de **debug** (signé avec la clé de debug) : adapté aux tests, pas à une publication sur le Play Store.

## Ce qui est réel, ce qui est simulé

- **Réel** : questions, chrono, score, réponse exacte, tirage sans répétition, progression sauvegardée sur l'appareil, bouton « Signaler une erreur ».
- **Simulé** : les classements mondiaux, les ligues, les autres joueurs. Il n'y a pas de serveur : votre rang est calculé à partir de joueurs fictifs. Un vrai classement demande un serveur (comptes, chrono côté serveur, anti-triche).
- **Hors ligne** : l'appli fonctionne sans réseau. Les polices Google ne sont pas embarquées, l'appli utilise les polices du système.

## La banque de questions (à vérifier)

Les 1 017 questions ont été **écrites de mémoire par un assistant IA, sans vérification source par source**. Les valeurs sont celles couramment citées (arrondies, avec « environ »), mais certaines peuvent être fausses ou dépassées, surtout les populations, les capacités de stades, les records et les chiffres de fréquentation. Avant toute diffusion hors de votre cercle de test :

1. Faites jouer, et utilisez **Signaler une erreur** à la révélation. Dans **Profil → Version test**, « Copier les signalements » place la liste (identifiant, question, valeur) dans le presse-papiers.
2. Corrigez les entrées dans `qs/*.py` (une ligne par question : `Y(...)` pour une année, `N(...)` pour une quantité), puis relancez `python3 build_questions.py && python3 build_app.py`.
3. Recommandation : recouper chaque valeur avec une source ouverte (Wikidata, Insee, data.gouv.fr) avant une vraie publication.

Répartition : Sport 127, Géographie 124, Nature 100, Transports 106, Territoires 119, Histoire 146, Sciences 162, Arts 133.

## Réglages utiles

- Durée du chrono : `TL` dans `app.template.html` (20 s).
- Questions par partie : 3, 5 ou 10, dans Profil → Version test.
- Points : `ptsFromS` (décroissance de la récompense selon la largeur) et `EXACT_PTS` (150).
- Identifiant de l'appli : `capacitor.config.json` (`app.fourchette.test`).
- Version de Capacitor : 7 (Node 20+, Java 21). Si une version plus récente est exigée par votre Android Studio, mettez à jour `package.json`.

## Fichiers

- `qs/` : les questions, une liste par thème. `build_questions.py` génère `questions.json` (échelles et repères calculés, contrôle des doublons et des bornes).
- `app.template.html` : l'application (gabarit). `build_app.py` produit `www/index.html`.
- `www/` : ce que Capacitor embarque dans l'APK.
- `assets/` : icône et écran de démarrage.
- `.github/workflows/build-apk.yml`, `build-apk.sh` : compilation.
