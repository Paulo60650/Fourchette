# La Fourchette — version de test Android

Jeu d'estimation : une fourchette fixe de 20 % de l'échelle part du milieu, on la fait glisser autour de son estimation. Bonne réponse au centre : 100 points, au bord : 50, dehors : 0. Valeur exacte : 150. 1 014 questions en 8 thèmes, chrono de 25 s, tout est vérifié par un serveur Supabase.

## Ce que contient l'appli

- **Parties** : aléatoires ou par thème, 3 / 5 / 10 questions ou illimité. Combo de centrage (réponses centrées à 80 % ou plus : ×1, ×1,2, ×1,5, ×2).
- **Défi du jour** : les mêmes 5 questions pour tous, une tentative, rang en direct, classement du jour, partage en grille d'emojis, série avec jokers (gel de série).
- **Mode Expert** : fourchette de 10 %, points doublés, débloqué à 80 questions classées.
- **Survie** : fourchette de 10 %, puis 8 % et 6 %, une vie bonus tous les 10 ; hors classement.
- **Duel** : 5 questions identiques par code envoyé en message ; hors classement.
- **Classements réels** : mondial (Niveau = moyenne par question, min. 10 ; Cumulé), sur 7 jours ou la saison (mois en cours, badge de fin de saison), général ou par thème, Monde ou France, avec rival.
- **Divisions hebdomadaires** : groupes de 30 (Bronze, Argent, Or, Diamant), top 5 promus, 5 derniers relégués.
- **Ligues entre amis** : création, code d'invitation, classement.
- **Progression** : niveaux et XP, 40 badges, coffre du jour, missions de la semaine, collection de cartes, couleurs à débloquer.
- **Accueil** : tient sur un écran (défi du jour, 4 modes, coffre / missions / division, 8 thèmes), thème clair par défaut ; « Sombre » et « Chaleureuse » dans Profil > Ambiance.
- **Compte** : anonyme au départ ; « Sécuriser mon compte » lie une adresse e-mail (code à 6 chiffres) pour le retrouver sur un autre téléphone.
- **Confort** : musique et effets synthétisés, vibrations, rappel quotidien (notification), signalement des questions douteuses.

## Mise en place du serveur (Supabase)

1. **Authentication > Sign In / Providers** : activer **Allow anonymous sign-ins** (comptes sans e-mail).
2. **SQL Editor**, dans l'ordre, chaque fichier collé puis **Run** :
   `server/01_schema.sql`, `server/02_questions_1.sql`, `_2`, `_3`, `server/03_fenetre_20.sql`, `server/04_addictif.sql`, `server/05_progression.sql`.
   Tous peuvent être relancés sans perte de données.
3. **E-mail (récupération de compte)** :
   - **Authentication > Emails > Templates** : dans « Magic Link » et « Change Email Address », ajouter le code `{{ .Token }}` au message (l'appli demande un code à 6 chiffres, pas un lien).
   - **Authentication > Emails > SMTP Settings** : brancher un SMTP (Brevo, Resend, etc.). L'expéditeur par défaut de Supabase n'écrit qu'aux membres de l'équipe du projet, avec un très petit quota.
4. `sbconfig.json` contient l'URL du projet et la clé **publique** (faite pour être dans l'appli). Ne jamais y mettre la clé `secret` / `service_role`.

Anti-triche : l'APK n'embarque aucune réponse. Le serveur envoie la question sans la réponse, chronomètre (25 s + 4 s de marge), vérifie la largeur de la fourchette, calcule les points et le combo, puis révèle la valeur.

## Compiler l'APK

- **GitHub Actions** (recommandé) : envoyer ce dossier sur GitHub ; l'action « Build APK de test » se lance à chaque envoi sur `main` et produit l'artefact `la-fourchette-test-apk` (`app-debug.apk`).
- **En local** : `./build-apk.sh` (Node 20+, Java 21, Android SDK).
- **Signature** : `signing/test-debug.keystore` (clé de test publique, mot de passe `android`) signe toujours de la même façon, et le numéro de version augmente à chaque compilation GitHub : les mises à jour s'installent par-dessus sans perdre la progression. Pour le Play Store, il faudra une vraie clé, gardée secrète.

## Modifier les questions

Éditer `qs/*.py`, puis :

```
python3 build_questions.py && python3 build_server_questions.py && python3 build_app.py
```

et recoller `server/02_questions_*.sql` dans le SQL Editor (mise à jour des questions existantes). Retirer une question : `update questions set active = false where id = 'SP001';`.

Les échelles sont générées pour que la bonne réponse tombe entre 10 % et 90 % de l'échelle (toujours centrable). Une fourchette laissée au milieu contient la réponse environ une fois sur quatre : c'est le plancher d'un départ centré.

**Vérification** : une passe de relecture complète a été faite (octobre 2026). Les corrections sont dans `qs/corrections.py` (par identifiant : énoncé, valeur, anecdote, ou `drop` pour retirer ; les identifiants ne bougent jamais). Les questions retirées sont désactivées à la fin de `02_questions_3.sql`. Continuez à utiliser « Signaler une erreur » (Profil > Version test > « Copier les signalements »).

## Données sur le téléphone

Tout est sur le serveur : scores, XP et niveau, badges, missions, coffre, jokers de série, couleurs, statistiques du Profil, classements, divisions, saisons, collection. Le téléphone ne garde que les réglages (son, ambiance, rappel). Une réinstallation repart d'un compte neuf, sauf si le compte a été sécurisé par e-mail (« J’ai déjà un compte »). Le Profil permet de supprimer le compte.

## L'aperçu dans Claude

`artifact.html` est une version de démonstration **sans serveur** : banque locale, classements et ligues simulés, pas de divisions ni de saisons.

## Réglages utiles

- Chrono : `TL` dans `app.template.html` (25 s) et `_tl()` dans le SQL.
- Fourchette : `FIX_W` (0,20) côté appli, `maxw` dans `submit_answer` côté serveur.
- Combo : `submit_answer` (serveur) et `API.submit` (aperçu).
- Questions par partie : Profil > Version test.
- Identifiant de l'appli : `capacitor.config.json` (`app.fourchette.test`). Capacitor 7 (Node 20+, Java 21).

## Fichiers

- `qs/*.py` : la banque de questions, un fichier par thème ; `qs/corrections.py` : les corrections.
- `build_questions.py` → `questions.json` ; `build_server_questions.py` → `server/02_questions_*.sql` ; `build_app.py` → `www/index.html` (APK) et `artifact.html` (aperçu).
- `app.template.html` : l'application (une seule page).
- `server/` : le schéma et les mises à jour SQL.
- `.github/workflows/build-apk.yml`, `build-apk.sh`, `capacitor.config.json`, `package.json`, `assets/`, `signing/`.
