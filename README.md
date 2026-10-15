# TaskFlow (version 1.1 – Firebase)

Flutter task management app. Login **Firebase Authentication** (email + password) se, aur data **Cloud Firestore** mein `users/{uid}/...` ke andar. Firestore phone par offline copy bhi rakhta hai, is liye app bina internet ke bhi chalti hai.

Security rules: `firestore.rules` (Firebase Console → Firestore → Rules mein paste karni hain).

APK link: https://github.com/adeelappdevzone-code/TaskFlow-APK/releases/latest/download/TaskFlow.apk

Bohat purane (32-bit) phone ke liye: https://github.com/adeelappdevzone-code/TaskFlow-APK/releases/latest/download/TaskFlow-old-phones.apk
(GitHub par sirf aakhri 5 builds rakhi jati hain.)

CI log: har build ka log aur result `ci-logs` branch mein save hota hai.

---

## APK kaise banayein

### Tareeqa 1: GitHub se (PC par kuch install nahi karna) ✅ Recommended

1. GitHub par free account banao aur ek **New repository** banao (naam: `taskflow`, Private bhi chalega).
2. Is project ka **saara content** repository mein upload karo:
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
| Register / Login | Firebase account (email + password), **Continue with Google**, password hide/show, forgot password (Firebase reset email) |
| Home | Greeting, unread notification badge, total/done/pending card + progress %, 4 shortcuts, aaj ke tasks |
| Tasks | All / Pending / Done tabs, search, filter (priority + category) |
| Add / Edit Task | Title*, description, category, priority, date, **start + end time**, project, assign to member, checklist |
| Task Detail | Status, priority, project, assignee, checklist tick + progress, Mark as Done, Edit / Cancel / Restore / Delete |
| Calendar | Sahi month grid (Monday se), task wale din par dot, select kiye din ke tasks, Today button |
| Projects | Progress % (done ÷ total), search, add/edit/delete, project ke andar tasks |
| Notifications | All / Tasks / System tabs: completed, assigned, reminder (15 min pehle), cancelled, project updates |
| Profile | Stats, Account Info (name, email change verify link se, password), Categories, Team Members, Settings & Backup (copy / restore / reset data), Help & FAQ, About, Logout |

Design ke bugs fix kar diye: calendar ki galat dates, din ka naam, single-time field (ab start + end), Add Task mein project aur checklist missing the.

## Folder structure

```
lib/
  main.dart                 Firebase start + login/home decide karta hai
  firebase_options.dart     Firebase project config (taskflow-ce905)
  core/theme.dart           colors, input style
  core/utils.dart           date/time helpers
  data/models.dart          User, Task, Category, Project, Member, ChecklistItem, Notification
  data/app_store.dart       saara login (Firebase Auth + Google) aur data read/write (Firestore) yahin
  data/reminders.dart       phone notifications (task se 15 min pehle)
  data/team_models.dart     Team, TeamInvite, roles
  data/team_store.dart      teams, team tasks, comments, invitations (Firestore)
  data/team_stats.dart      dashboard ke numbers (pending, overdue, har member ka kaam)
  screens/                  har screen ki file
  widgets/common.dart       shared UI (TaskTile, buttons, chips...)
firestore.rules             Firestore security rules (Console mein paste karni hain)
tool/setup_android.sh       app ka naam, icon, minSdk 23 set karta hai
tool/rules_test/          firestore.rules ke tests (Firestore emulator, CI mein chalte hain)
test/                     unit tests (`flutter test`)
tool/debug.keystore         APK signing key (sirf testing; Play Store se pehle badalni hai, TODO.md dekho)
```

## My Day, Board, Repeat, Templates

- **My Day** (Home): aaj ke aur late (overdue) kaam ek jagah — personal tasks bhi aur teams ke wo
  tasks jo aap ko assign hain (team ka naam sath likha hota hai).
- **Board view** (team screen par 🗂 icon): columns *To do / In progress / Review / Done*. Card ko
  lamba daba kar doosre column mein le jao. Owner/Manager koi bhi card, member sirf apna. Task ke
  andar bhi *To do / In progress / Review* buttons hain.
- **Repeat**: task form mein *Every day / week / month*. Task Done karte hi agli copy apne aap ban
  jati hai (agli tareekh par, checklist khali). Late done ho to guzre hue din skip hote hain.
- **Templates**: task form ke upar 🔖 button. Kisi task ko template bana kar save karo (title,
  description, priority, checklist), phir ek tap mein naya task usi se bharo. Template lamba daba
  kar delete.

## Teams

- **Teams** tab → **New team** (jaise "SEO"). Banane wala us team ka **Owner** hai.
- **Members → Add person by email**: wo email daalo jis se banda TaskFlow mein login karta hai.
  Usay Teams tab mein invitation dikhegi (**Accept / Decline**). App baad mein install kare to bhi
  invitation intezar karti hai.
- Accept karne ke liye email **verified** honi chahiye (Google login wale hamesha verified hain;
  email/password wale ko verify link bheja jata hai), taake koi kisi aur ke email se join na kar sake.
- Roles:
  - **Owner**: sab kuch (team edit/delete, manager banana, kisi ko bhi nikalna)
  - **Manager**: log add karna, members ko nikalna, tasks banana / edit / assign karna
  - **Member**: team aur us ke tasks dekhna, apna task Done karna aur checklist tick karna
- **Overview** tab (sirf Owner/Manager): pending / overdue / is hafte done, har banday ka kaam
  (kitne pending, late, done) aur late tasks ki list. Teams tab ke upar saari teams ka khulasa.
- **Weekly report** (Owner/Manager: team ⋮ menu ya Overview tab): hafta (Mon–Sun) ka khulasa —
  kis ne kitne kaam done kiye, kya late hai, done/late tasks ki list. **Share as image** ya
  **Share as text (WhatsApp)**. Tiron se pichle hafte bhi dekh sakte ho.
- **Comments**: har team task par team ka koi bhi banda update likh sakta hai ("50% ho gaya").
  Apna comment (ya Owner/Manager koi bhi) lamba daba kar delete hota hai. Jis ka task hai
  (assign hua / assign kiya) usay naye comment ki notification aati hai.
- Naya task assign ho, invitation aaye ya koi team join kare to notification aati hai (jab app
  khuli ho ya abhi abhi band ki ho). Assigned tasks ke 15-minute reminders bhi aate hain.
- Data: `teams/{teamId}` (members, roles), `teams/{teamId}/tasks/...`,
  `teams/{teamId}/comments/...`, `invites/{teamId}_{email}`.
  Ijazatein `firestore.rules` mein lagti hain (tests: `tool/rules_test`).

## Data kahan aur kaise save hota hai

- Har user ka data Firestore mein `users/{uid}/` ke andar: `categories`, `projects`, `members`, `tasks` (checklist task ke andar), `notifications`.
- Firestore phone par offline copy rakhta hai: bina internet ke changes foran dikhte hain aur internet aate hi upload ho jate hain.
- Isi account se kisi bhi phone par login karo, saara data wapas aa jata hai.
- Har record ki ID **UUID** hai.

## Google login ki setup (Firebase Console)

- Authentication → Sign-in method → **Email/Password** aur **Google** dono enabled.
- Project settings → Your apps → Android app (`com.potens.taskflow`) mein APK signing key ka **SHA-1** add hona chahiye:
  `2E:55:DD:AF:09:A3:0D:93:7E:75:2B:06:C1:80:04:67:FE:81:7F:59` (`tool/debug.keystore` ka).
  Ye na ho to Google ka popup account select karne ke baad band ho jata hai.

## Abhi ki limitations

- Reminders: task shuru hone se 15 minute pehle phone notification aati hai (app band ho tab bhi,
  phone restart ke baad bhi). Android idle ho to kabhi kabhi do-chaar minute late aa sakti hai.
  Notification sirf usi phone par aati hai jahan app mein login ho.
- Assign to member: abhi sirf naam hai, us member ko koi notification nahi jati.
- Baqi kaam ki list: `TODO.md`.
