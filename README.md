# Smart Dukan

**Aapka hisaab, sirf aapke phone par.**

Offline-first Android app for Pakistani shopkeepers (starting with mobile
phone shops): sales, stock, udhaar, cash and khata — all on the phone, no
login, no server.

Built milestone by milestone from the *Smart Dukan v2 — AI Build
Specification*. Decisions that differ from or clarify the spec are in
[DECISIONS.md](DECISIONS.md).

## Status

| # | Milestone | Status |
|---|---|---|
| 1 | Project foundation | ✅ Code written — **needs first run on a phone** |
| 2 | Database and money core | ⏳ Next |
| 3 | Onboarding, PIN, settings | — |
| 4 | Products and stock | — |
| 5 | Sales (POS) | — |
| 6 | Purchases, parties, payments, expenses | — |
| 7 | Dashboard, Galla Band, reports | — |
| 8 | Mobile Shop Pro | — |
| 9 | License, backup, security hardening | — |
| 10 | Polish and release | — |

## First-time setup

Needs Flutter (stable) and Android Studio / Android SDK.

```bash
git clone <this repo>
cd smart_dukan

# 1. Generate the Android platform folder (does not touch lib/ or test/)
flutter create --platforms=android --org pk.smartdukan --project-name smart_dukan .

# 2. Set minSdk to 26 (Android 8.0) — spec Section 6
#    In android/app/build.gradle.kts change:  minSdk = flutter.minSdkVersion
#    to:                                       minSdk = 26

# 3. Get packages (also generates the language files)
flutter pub get

# 4. Run the tests
flutter test

# 5. Run on your phone (USB debugging on)
flutter run
```

If `flutter pub get` complains about versions, run
`flutter pub upgrade --major-versions` once and commit the updated
`pubspec.yaml` and `pubspec.lock`.

## Milestone 1 — what is built

- Folder structure from spec Section 6 (`lib/app`, `lib/core`, `lib/features/...`).
- Material 3 theme with every colour token from Section 4, light + dark mode.
- Typography scale (Display/Title/Body/Label/Caption) with tabular figures;
  Urdu uses Nastaliq/Naskh with taller line height.
- Three languages: English, Roman Urdu (default), Urdu (full RTL mirroring;
  numbers stay LTR). Switch in **Aur → Zubaan**.
- go_router with bottom navigation: Home, Sale, Khata, Stock, Aur, and the
  centre **+ Nayi Sale** button.
- Home "Aaj ka Hisaab" layout: 8 stat cards, 6 quick actions, recent activity.
- Reusable widgets in `lib/core/widgets/`: `StatCard`, `AmountKeypad`
  (big keys + "000"), `PartyTile`, `EmptyState`, `PrimaryButton`
  (double-tap safe), `ConfirmSheet`.
- `Money` type in integer paisa + `Rs 125,000` formatter (no lakh grouping).
- Tests: money maths/formatting, keypad input, app launch, every tab, all
  3 languages × light/dark without overflow, RTL check.

### Screens (what you should see)

- **Home** — "Aaj ka Hisaab", today's date, green "Offline • Mehfooz" badge;
  2-column cards: Aaj ki Sale, Galla, Lena (green ↙), Dena (red ↗),
  Aaj ka Munafa, Kam Stock, Aaj ki Qist (PRO), Repair Tayyar (PRO) — all Rs 0;
  6 quick-action tiles; "Abhi koi entry nahi" empty state.
- **Sale** — "Nayi Sale" title and an empty state asking to add stock first.
- **Khata** — Gahak / Supplier tabs, each with an empty state.
- **Stock** — empty state with "Maal Add Karein".
- **Aur** — language and theme switches, app version and tagline.

Buttons that belong to later milestones show "Yeh feature agle update mein
aa raha hai."

### Known gaps

- Fonts not bundled yet — see `assets/fonts/README.md`.
- Language/theme choice resets on restart (saved to the DB in Milestone 2).
- The `android/` folder is generated on your machine (step 1 above).
