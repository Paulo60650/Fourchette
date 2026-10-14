#!/usr/bin/env bash
# Compilation locale de l'APK de test. Prérequis : Node 20+, Java 21, Android SDK (ANDROID_HOME défini), Python 3.
set -euo pipefail
cd "$(dirname "$0")"
python3 build_questions.py
python3 build_app.py
npm install
[ -d android ] || npx cap add android
npx @capacitor/assets generate --android --iconBackgroundColor '#12062B' --splashBackgroundColor '#12062B' || echo "Icône par défaut conservée"
grep -q 'screenOrientation' android/app/src/main/AndroidManifest.xml || \
  sed -i.bak 's#<activity#<activity android:screenOrientation="portrait"#' android/app/src/main/AndroidManifest.xml
npx cap sync android
(cd android && ./gradlew assembleDebug)
echo
echo "APK prêt : android/app/build/outputs/apk/debug/app-debug.apk"
