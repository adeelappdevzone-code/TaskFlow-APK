#!/usr/bin/env bash
# Run once after `flutter create` has generated the android/ folder.
# - App name "TaskFlow" + launcher icons
# - minSdk 23 (required by Firebase Auth / Firestore)
set -e
cd "$(dirname "$0")/.."
MANIFEST=android/app/src/main/AndroidManifest.xml
if [ ! -f "$MANIFEST" ]; then
  echo "android/ folder not found. Run first:"
  echo "  flutter create --platforms=android --org com.potens --project-name taskflow ."
  exit 1
fi

# App name
sed -i.bak -E 's/android:label="[^"]*"/android:label="TaskFlow"/' "$MANIFEST" && rm -f "$MANIFEST.bak"

# Launcher icons
for d in assets/launcher/mipmap-*; do
  name=$(basename "$d")
  mkdir -p "android/app/src/main/res/$name"
  cp "$d/ic_launcher.png" "android/app/src/main/res/$name/ic_launcher.png"
done

# minSdk 23 (works for both build.gradle and build.gradle.kts templates)
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] || continue
  sed -i.bak -E \
    -e 's/minSdk[[:space:]]*=[[:space:]]*flutter\.minSdkVersion/minSdk = 23/' \
    -e 's/minSdkVersion[[:space:]]+flutter\.minSdkVersion/minSdkVersion 23/' \
    "$f" && rm -f "$f.bak"
  echo "minSdk lines in $f:"; grep -nE "minSdk" "$f" || true
done

echo "Android app name, icon and minSdk set."
