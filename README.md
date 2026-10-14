# TaskFlow (version 1.1 – Firebase)

Flutter task management app. Login **Firebase Authentication** (email + password) se, aur data **Cloud Firestore** mein `users/{uid}/...` ke andar. Firestore phone par offline copy bhi rakhta hai, is liye app bina internet ke bhi chalti hai.

Security rules: `firestore.rules` (Firebase Console → Firestore → Rules mein paste karni hain).

APK link: https://github.com/adeelappdevzone-code/TaskFlow-APK/releases/latest/download/TaskFlow.apk

CI log: har build ka log aur result `ci-logs` branch mein save hota hai.

---

## APK kaise banayein

### Tareeqa 1: GitHub se (PC par kuch install nahi karna) ✅ Recommended

1. GitHub par free account banao aur ek **New repository** banao (naam: `taskflow`, Private bhi chalega).
2. Is zip ke andar ka **saara content** repository mein upload karo:
   repo page → **Add file → Upload files** → saari files/folders drag karo → **Commit changes**.
   > Dhyan rahe `.github` folder bhi upload ho. Agar browser hidden folder na dikhaye to GitHub Desktop app use karo.
3. Repo mein **Actions** tab kholo. "Build APK" chalna shuru ho jayega (5–8 minute).
4. Green ✓ aane par us run ko kholo → neeche **Artifacts** mein `TaskFlow-APK` download karo.
5. Zip kholo → `app-release.apk` phone mein bhejo → install karo.
   (Phone "Unknown sources / Install unknown apps" ki permission maangega, allow kar do.)

Agla code change upload karoge to Actions khud nayi APK bana dega.

### Tareeqa 2: Apne PC par

Zaroorat: [Flutter SDK](https://docs.flutter.dev/get-started/install) + Android Studio (Android SDK ke liye).

```bash
cd taskflow
flutter create --platforms=android --org com.potens --project-name taskflow .
bash tool/setup_android.sh        # app ka naam "TaskFlow" + icon (Windows par Git Bash se chalao)
flutter pub get
flutter build apk --release
```

APK yahan milegi: `build/app/outputs/flutter-apk/app-release.apk`

Phone USB se laga kar seedha chalana ho (USB debugging ON): `flutter run`

---

## App mein kya hai

| Screen | Features |
|---|---|
| Onboarding | Get Started, Login link |
| Register / Login | Local account, password hide/show, forgot password (offline reset), Google button (cloud version mein) |
| Home | Greeting, unread notification badge, total/done/pending card + progress %, 4 shortcuts, aaj ke tasks |
| Tasks | All / Pending / Done tabs, search, filter (priority + category) |
| Add / Edit Task | Title*, description, category, priority, date, **start + end time**, project, assign to member, checklist |
| Task Detail | Status, priority, project, assignee, checklist tick + progress, Mark as Done, Edit / Cancel / Restore / Delete |
| Calendar | Sahi month grid (Monday se), task wale din par dot, select kiye din ke tasks, Today button |
| Projects | Progress % (done ÷ total), search, add/edit/delete, project ke andar tasks |
| Notifications | All / Tasks / System tabs: completed, assigned, reminder (15 min pehle), cancelled, project updates |
| Profile | Stats, Account Info (name/email/password), Categories, Team Members, Settings & Backup, Help & FAQ, About, Logout |

Design ke bugs fix kar diye: calendar ki galat dates, din ka naam, single-time field (ab start + end), Add Task mein project aur checklist missing the.

## Folder structure

```
lib/
  main.dart                 app start + login/home decide karta hai
  core/theme.dart           colors, input style
  core/utils.dart           date/time helpers
  data/models.dart          User, Task, Category, Project, Member, ChecklistItem, Notification
  data/database.dart        SQLite tables
  data/app_store.dart       repository: saare read/write yahin (cloud sync baad mein yahin lagega)
  screens/                  har screen ki file
  widgets/common.dart       shared UI (TaskTile, buttons, chips...)
```

## Cloud ke liye tayari (sync-ready)

- Har record ki ID **UUID** hai (do phones ki IDs nahi takrayengi)
- Har table mein `created_at`, `updated_at`, `deleted_at` (soft delete), `is_synced`
- Screens database se seedha baat nahi karti, sab `AppStore` se hota hai. Cloud version mein sirf isi file mein API calls add hongi.

## Abhi ki limitations (jaan boojh kar)

- Data sirf is phone mein hai. App uninstall = data khatam. **Settings → Copy backup** se backup rakho.
- Ek phone par ek account.
- Reminders sirf jab app khuli ho (in-app). Band app par phone notification agle version mein.
- Assign to member: abhi sirf naam hai, doosre user ko notification cloud version mein jayegi.
