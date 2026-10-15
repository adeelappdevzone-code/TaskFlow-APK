# Baad ke kaam (TODO)

## Play Store se pehle: apni release signing key

Abhi CI har APK `tool/debug.keystore` se sign karta hai, aur ye key repo mein hai.
Repo private hai aur app sirf apne phone par chal rahi hai, is liye abhi theek hai.
**Play Store par daalne se pehle ye zaroor karna hai:**

1. Nayi release keystore banao (repo mein commit NAHI karni).
2. GitHub → Settings → Secrets and variables → Actions mein 4 secrets daalo:
   `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
3. `.github/workflows/build-apk.yml` ko badlo taake APK in secrets se sign ho.
4. `tool/debug.keystore` repo se hata do.
5. Nayi key ka SHA-1 (aur SHA-256) Firebase → Project settings → Android app mein
   add karo, warna Google login band ho jayega.
6. Keystore + passwords ki copy mehfooz jagah rakho. Ye gum hui to Play Store par
   app kabhi update nahi ho sakegi.

Dhyan: key badalne ke baad phone se purani app ek dafa uninstall karni hogi
(data Firebase mein hai, login karte hi wapas aa jayega).

## Teams: agle phase

- Phase 3 (Blaze plan + Cloud Functions): app band ho tab bhi assign hone par push notification.
- Profile ka "Team Members" (sirf naam, personal tasks ke liye) asli Teams se alag hai; baad mein
  isay hata dena ya "Contacts" naam dena.

## Review se baqi kaam

- Flutter CI mein 3.47.7 par fix hai (`build-apk.yml`). Upgrade karte waqt CI log check karo.
  Wahan "plugins that apply Kotlin Gradle Plugin (KGP): firebase_auth, firebase_core" wali
  warning ghalat alarm hai: Flutter sirf plugin ki file mein text dhoondta hai, jabke Firebase
  plugins Kotlin plugin tabhi lagate hain jab AGP 9 se purana ho (hamara 9.1 hai).
  Agar kabhi is warning ki wajah se build fail ho, to firebase packages naye version par update karo.
- Tests: abhi models, utils, reminders aur Firestore rules ke hain. Screens (widget) tests nahi.
- `firestore.rules` badlo to Firebase Console → Firestore → Rules mein paste kar ke Publish karna
  zaroori hai (CI rules ko sirf test karta hai, Firebase par khud nahi lagata).
