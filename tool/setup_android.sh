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

# Sign every build (debug + release) with tool/debug.keystore, so the APK's
# SHA-1 always matches the one added in Firebase (needed for Google login) and
# a new APK installs as an update. Copying it to ~/.android is not enough: the
# build may look for the debug key somewhere else and create a random one.
if [ -f android/app/build.gradle.kts ] && ! grep -q "tool/debug.keystore" android/app/build.gradle.kts; then
  cat >> android/app/build.gradle.kts <<'EOF'

android {
    signingConfigs {
        getByName("debug") {
            storeFile = rootProject.file("../tool/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
}
EOF
elif [ -f android/app/build.gradle ] && ! grep -q "tool/debug.keystore" android/app/build.gradle; then
  cat >> android/app/build.gradle <<'EOF'

android {
    signingConfigs {
        debug {
            storeFile rootProject.file("../tool/debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }
}
EOF
fi

echo "Android app name, icon, minSdk and signing key set."
