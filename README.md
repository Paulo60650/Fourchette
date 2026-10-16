# La Fourchette — version de test Android

Application d'estimation par fourchettes : on encadre une valeur, plus c'est serré, plus ça rapporte, et hors fourchette c'est 0 point. Cette version contient **1 017 questions** réparties en 8 thèmes, des parties aléatoires ou par thème, un chrono de 25 s, la réponse exacte (150 points), un classement « niveau » et « cumulé », et deux ambiances (Vif / Chaleureuse).

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

- Durée du chrono : `TL` dans `app.template.html` (25 s).
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

## Profil vierge

Au premier lancement, tout est à zéro : aucune statistique, série ou badge fictif. Le profil, la série de jours, les graphiques et les moyennes viennent uniquement de vos réponses (stockées sur l'appareil). Le rang « Niveau » apparaît après 10 questions. Seuls les autres joueurs du classement et des ligues restent simulés.

## Badges, son, survie

- **32 badges** (paliers de questions, de parties, de jours de suite et de points, exploits : valeur exacte, séries sans faute, partie parfaite, réponse éclair, survie…). Animation de déblocage (médaille, rayons, confettis). Définitions : tableau `BD` dans `app.template.html`.
- **Musique** : synthétisée en direct (Web Audio), aucun fichier audio. Une ambiance pour jouer, une plus rythmée en survie, un jingle distinct pour les badges. Réglages dans Profil > Son, haut-parleur sur l'écran de question. Coupée quand l'application passe en arrière-plan. Presets : objet `PRE`.
- **Mode survie** : fenêtre fixée à 10 % de l'échelle, que l'on déplace. Une erreur et la partie s'arrête. Compte pour les badges de survie, pas pour les classements Niveau et Cumulé.

## Mises à jour sans désinstaller

Le dossier `signing/` contient une clé de signature de test, toujours la même. Chaque APK compilé (GitHub Actions ou `build-apk.sh`) est signé avec elle, et le numéro de version augmente à chaque compilation sur GitHub : la nouvelle version s'installe par-dessus l'ancienne et garde la progression des testeurs.

- Une seule fois : les testeurs qui ont un APK compilé avant cette clé doivent le désinstaller (sa signature est différente).
- Cette clé est publique (mot de passe `android`) : elle ne sert qu'aux tests. Pour le Play Store, il faudra une vraie clé, gardée secrète et jamais déposée dans le dépôt.
- Ne supprimez pas `signing/test-debug.keystore` : sans elle, retour à la désinstallation obligatoire.

## Défi du jour, niveaux, duel, rappels

- **Défi du jour** : 5 questions tirées pour chaque joueur, une seule tentative par jour (quitter en cours compte comme tentative). Série de défis dédiée et 4 badges.
- **Niveaux** : 5 XP plus les points par question, 20 XP par question réussie en survie, 100 XP par défi, 50 XP par badge. Titres : Novice, Curieux, Estimateur, Fin estimateur, Expert, Maître des fourchettes, Grand maître, Légende vivante. Animation à chaque niveau.
- **Survie** : fenêtre de 10 %, puis 8 % après 10 réussites et 6 % après 20. Une vie bonus tous les 10 réussites.
- **Duel** : sans serveur, par code. Le joueur A joue 5 questions et envoie un code F1. B le colle, joue les mêmes questions et renvoie un code F2 que A colle pour voir le résultat. Les codes contiennent les identifiants des questions : si la banque change (ids renumérotés), les anciens codes deviennent incompatibles.
- **Rappel quotidien** : notification locale à l'heure choisie (Profil), ignorée le jour où le défi est déjà joué. Android 13+ demande l'autorisation à l'activation.
- **Retours** : petit son juste / serré / raté / exact et vibration à la révélation, réglables dans Profil > Son et vibrations.
- Extensions Capacitor ajoutées : `@capacitor/local-notifications`, `@capacitor/haptics`, `@capacitor/share` (installées par `npm install`, aucune autre action).

## Serveur (Supabase) : comptes, vrais classements, ligues, défi commun

L'APK se connecte au projet Supabase indiqué dans `sbconfig.json` (URL + clé publique, faite pour être dans l'appli). L'aperçu dans Claude reste en mode local (sans serveur).

### Mise en place (une seule fois)
1. Supabase > **Authentication > Sign In / Providers** : activer **Allow anonymous sign-ins**.
2. Supabase > **SQL Editor** > New query : coller tout `server/01_schema.sql`, **Run**. (Si Supabase avertit d'une « opération destructive », confirmer : ce sont des `drop … if exists` sans effet sur les données.)
3. Même chose avec `server/02_questions_1.sql`, puis `_2`, puis `_3` (la banque de questions).
4. Vérifier : **Table Editor > questions** doit afficher 1 017 lignes.

### Ce que fait le serveur
- **Chrono et score côté serveur** : la question part sans la réponse ; le serveur note l'heure d'envoi, refuse les réponses arrivées après 25 s + 4 s de marge (0 point), calcule les points et ne renvoie la vraie valeur qu'après la réponse. Une question abandonnée compte 0.
- **L'APK n'embarque plus la banque** : les réponses ne sont que sur le serveur.
- **Défi du jour commun** : les mêmes 5 questions pour tous (une par thème, tirées le jour même, heure de Paris), une seule tentative, reprise possible si l'appli se ferme, **rang en direct** après chaque question et classement du jour.
- **Classement mondial réel** : Niveau (moyenne par question, min. 10 questions) et Cumulé, sur 7 ou 28 jours, général ou par thème, Monde ou France (pays déduit de la langue du téléphone).
- **Ligues** : créer, inviter par code, rejoindre, quitter ; classement sur 7 ou 28 jours.
- **Comptes** : anonymes (pas d'e-mail), pseudo unique à choisir au premier lancement, suppression du compte depuis le Profil (exigé par le Play Store).
- La survie et les duels passent aussi par le serveur (questions et score) mais ne comptent pas dans les classements.

### Modifier les questions
Éditer `qs/*.py`, puis `python3 build_questions.py && python3 build_server_questions.py`, et recoller les fichiers `server/02_questions_*.sql` dans le SQL Editor (les questions existantes sont mises à jour). Pour retirer une question : `update questions set active = false where id = 'SP001';`.

### Test local du serveur
`server/01_schema.sql` a été testé sur Postgres 16 avec une imitation minimale de Supabase (rôles, `auth.users`, `auth.uid()`), et l'appli de bout en bout contre un faux serveur Supabase local : comptes, parties, défi du jour (reprise, rang en direct), classements, ligues, duel, survie, suppression de compte.
