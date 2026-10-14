#!/usr/bin/env bash
# Run once after `flutter create` has generated the android/ folder.
# Sets the app name to "TaskFlow" and installs the launcher icons.
set -e
cd "$(dirname "$0")/.."
MANIFEST=android/app/src/main/AndroidManifest.xml
if [ ! -f "$MANIFEST" ]; then
  echo "android/ folder not found. Run first:"
  echo "  flutter create --platforms=android --org com.potens --project-name taskflow ."
  exit 1
fi
sed -i.bak -E 's/android:label="[^"]*"/android:label="TaskFlow"/' "$MANIFEST" && rm -f "$MANIFEST.bak"
for d in assets/launcher/mipmap-*; do
  name=$(basename "$d")
  mkdir -p "android/app/src/main/res/$name"
  cp "$d/ic_launcher.png" "android/app/src/main/res/$name/ic_launcher.png"
done
echo "Android app name and icon set."
