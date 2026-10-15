# TaskFlow — handover + baqi kaam (TODO)

Nayi chat / naya Claude: pehle ye file aur `README.md` parho. Owner Roman Urdu mein baat karta hai,
aksar akela kaam karta hai, PR/merge nahi chahta: **changes seedha `main` par push karo**
(branch `claude/cool-maxwell-b6rodp` bhi sath update karo). Test pehle khud karo, phir push.
**Jawab chhota rakho:** kaam ke dauran updates/tafseel nahi, aakhir mein sirf 3-5 lines (kya bana, tests pass, push/CI ok).

## REDESIGN chal raha hai (Oct 2026) — pehle ye parho

Testing team ne app reject ki: tasks do jagah bikhre hue, har page par wahi stats. Naya plan:
- **Ek task system:** storage wahi (`users/{uid}/tasks` + `teams/{id}/tasks`), lekin app mein ek
  `TaskRepository` sab tasks ek list mein deta hai (task + team ya null). Ek Create sheet
  (Personal / kaunsi Team), ek Task detail har jagah.
- **Home** = aaj ka focus (My Day, Needs attention, Upcoming). **My Tasks** = personal + mujhe
  assigned team tasks (+ "Assigned by me" filter). **Calendar** mein assigned team tasks bhi.
  **Team** = Tasks (List/Board) / Members / Overview (sirf admin, weekly report yahin).
  **Profile** = sirf account + settings (stats hatao). Sidebar: Home, My Tasks, Calendar, Teams
  (har team ka link), Notifications, Profile, + New Task.
- **Member bhi team mein task bana sakta hai** (apne liye) — rules badalne honge.
- Owner screen by screen UI dega (10 screens). **Jab tak 10 screens poori na hon, `main` par push
  NAHI** (main par push = APK + web build). Kaam sirf branch `claude/cool-maxwell-b6rodp` par
  push karo; 10 poori hone par ek dafa `main` par, phir mobile + desktop test.
- Contacts (personal task kisi naam ko assign) **hata diye** — assign sirf Teams mein.
- Screens: 1 ✅ Home, 2 ✅ My Tasks, 6 ✅ Teams list (invitations upar, grid/list, "N for you", Create new team card), 5 ✅ Calendar (Day/Week/Month, personal + assigned team tasks, khali slot par click = naya task), 4 ✅ Task page (personal + team ek hi; laptop par page ke upar khulta hai, sidebar rehta hai), 3 ✅ Create task dialog (har jagah se ek hi; bina time = All day; Google Calendar link; "More options" = poora form) (personal + assigned, filter: team/project, "Assigned by me"; table/board). Home: naya sidebar + top bar search/bell/account; My Day mein team/project/
  Personal chip). Baqi 9 owner bhejega.

## Setup (sab chal raha hai)

- **App:** Flutter 3.47.7 (CI mein fix), Firebase project `taskflow-ce905` (Spark/free plan, card nahi).
- **CI** `.github/workflows/build-apk.yml`, `main` par har push:
  1. `build` job: analyze, `flutter test`, Firestore rules tests (`tool/rules_test`, emulator),
     APK (arm64 + 32-bit) `tool/debug.keystore` se sign, signing key check, GitHub Release
     (sirf aakhri 5 rakhta hai). Log → branch `ci-logs` (`status.txt`, `build.log`).
  2. `web` job: `flutter build web` → Firebase Hosting **https://taskflow-ce905.web.app**, aur
     **`firestore.rules` khud publish** (secret `FIREBASE_SERVICE_ACCOUNT`, roles Firebase Admin +
     Service Usage Consumer). Log → branch `ci-logs-web`.
- **APK link:** https://github.com/adeelappdevzone-code/TaskFlow-APK/releases/latest/download/TaskFlow.apk
- **Firebase Console mein ho chuka:** SHA-1 `2E:55:DD:AF:09:A3:0D:93:7E:75:2B:06:C1:80:04:67:FE:81:7F:59`,
  Google + Email/Password login on, Web app "TaskFlow Web" registered (`lib/firebase_options.dart`).
- `android/` aur `web/` folders CI mein `flutter create` se bante hain; badlav `tool/setup_android.sh`
  aur `tool/setup_web.sh` mein karo (manifest receivers, desugaring, signing, naam/icon).
- `test/widget_test.dart` ka naam mat badlo (warna `flutter create` default test daal deta hai).
- Is container mein Flutter nahi hota: `git clone --depth 1 -b 3.47.7 https://github.com/flutter/flutter.git`
  kar ke `flutter analyze lib test` + `flutter test` chalao. Rules tests: `cd tool/rules_test && npm install && npm test`.
- Laptop layout ki tasveer check karni ho: widget test mein `tester.view.physicalSize = Size(1600,1000)`
  aur `matchesGoldenFile` + `--update-goldens` (sirf dekhne ke liye, commit mat karo).

## Ab tak kya bana (sab live)

- Personal tasks: categories, projects, checklist, priority, start/end time, **repeat**
  (daily/weekly/monthly, done par agli copy), **templates**, calendar, notifications, backup/restore.
- **Teams:** create, invite by email (verified email zaroori), roles Owner/Manager/Member,
  team tasks assign, **board** (To do/In progress/Review/Done, drag), comments, Overview dashboard,
  **weekly report** (image/WhatsApp text), recent activity, `completed_by`.
- **My Day** (Home), phone reminders (local notifications, waqt Profile se: off/5/15/30/60 min),
  team alerts on/off, in-app notifications.
- **Web version** + **laptop layout** (900px+): side menu, task detail panel daayen, laptop design
  Teams / Team (Tasks/Members/Overview) / Tasks / Profile; phone layout alag.
- **Profile:** job title, role, stats, quick settings, focus ring, preferences, security
  (login method, password, email verification), recent activity.
- **@mention** comments, **task history**, **time tracking** (Start/Stop, Home banner, weekly
  report), **task links** (Drive/Docs/website).
- Firestore rules: har collection validated; ~114 rules tests. Flutter: ~58 tests.

## Agla batch (owner se baat ho chuki, ye mashwara diya tha)

Ho chuke (Oct 2026): **@mention**, **task history**, **time tracking** (weekly report mein bhi),
**task links**. README ka "@mention, History, Time tracking, Links" hissa dekho.

Baqi:
1. **Performance graph** — member ka hafta-dar-hafta done vs late (4–8 hafte) + ghante.
2. **Dark mode** — Profile → Preferences mein Light/Dark (abhi colors hard-coded hain `AppColors`).
3. **Excel/CSV export** (time log bhi), **Urdu zaban**, **Android home screen widget**.
4. Chhoti cheezein: time entry ko baad mein edit/delete karna, template mein links.

Card / Blaze plan chahiye (abhi nahi): asli push notifications (app band ho tab bhi),
files/photos attach, email alerts.

## Play Store se pehle: apni release signing key

Abhi CI har APK `tool/debug.keystore` se sign karta hai, aur ye key repo mein hai.
Repo private hai aur app sirf apne phone par chal rahi hai, is liye abhi theek hai.
**Play Store par daalne se pehle ye zaroor karna hai:**

1. Nayi release keystore banao (repo mein commit NAHI karni).
2. GitHub → Settings → Secrets and variables → Actions mein 4 secrets daalo:
   `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
3. `.github/workflows/build-apk.yml` aur `tool/setup_android.sh` ko badlo taake APK in secrets se
   sign ho (aur CI ka SHA-1 check naye SHA-1 par).
4. `tool/debug.keystore` repo se hata do.
5. Nayi key ka SHA-1 (aur SHA-256) Firebase → Project settings → Android app mein
   add karo, warna Google login band ho jayega.
6. Keystore + passwords ki copy mehfooz jagah rakho. Ye gum hui to Play Store par
   app kabhi update nahi ho sakegi.
7. Privacy policy aur store listing.

Dhyan: key badalne ke baad phone se purani app ek dafa uninstall karni hogi
(data Firebase mein hai, login karte hi wapas aa jayega).

## Notes

- Flutter CI mein 3.47.7 par fix hai. Upgrade karte waqt CI log check karo. "plugins that apply
  Kotlin Gradle Plugin (KGP): firebase_auth, firebase_core" wali warning ghalat alarm hai (Firebase
  plugins KGP tabhi lagate hain jab AGP < 9; hamara 9.1). Build fail ho to firebase packages update karo.
- Is container ka network `gstatic.com` aur `*.web.app` block karta hai, is liye web app yahan
  browser mein nahi chal sakti — check owner karta hai.
- Profile ka "Contacts" (pehle "Team Members") sirf personal tasks ke naam hain, asli Teams se alag.
