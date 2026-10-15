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

# Phone reminders (flutter_local_notifications):
# - receivers that show scheduled notifications and re-create them after a
#   phone restart, + the boot permission
# - Java "desugaring", which the plugin needs on older Android versions
if ! grep -q "ScheduledNotificationReceiver" "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
perm = '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    '
receivers = """<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    """
i = s.index("<application")
s = s[:i] + perm + s[i:]
j = s.rindex("</application>")
s = s[:j] + receivers + s[j:]
open(p, "w").write(s)
PY
fi
if [ -f android/app/build.gradle.kts ] && ! grep -q "desugar_jdk_libs" android/app/build.gradle.kts; then
  sed -i -E 's/^([[:space:]]*)compileOptions[[:space:]]*\{/&\n\1    isCoreLibraryDesugaringEnabled = true/' android/app/build.gradle.kts
  cat >> android/app/build.gradle.kts <<'EOF'

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
EOF
elif [ -f android/app/build.gradle ] && ! grep -q "desugar_jdk_libs" android/app/build.gradle; then
  sed -i -E 's/^([[:space:]]*)compileOptions[[:space:]]*\{/&\n\1    coreLibraryDesugaringEnabled true/' android/app/build.gradle
  cat >> android/app/build.gradle <<'EOF'

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
EOF
fi
grep -nE "esugar" android/app/build.gradle* || true

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

echo "Android app name, icon, minSdk, reminders and signing key set."
