# Smart Dukan

**Aapka hisaab, sirf aapke phone par.**

Offline-first Android app for Pakistani shopkeepers, starting with mobile
phone shops: sales, stock, udhaar, cash and khata — all on the phone, in an
encrypted database. No login, no server, no ads, works in airplane mode.

Built from the *Smart Dukan v2 — AI Build Specification*. Every place where
the spec was unclear or had to be adapted is recorded in
[DECISIONS.md](DECISIONS.md).

## Status

| # | Milestone | Status |
|---|---|---|
| 1 | Project foundation | ✅ |
| 2 | Database and money core | ✅ worked example + every posting rule tested |
| 3 | Onboarding, PIN, settings | ✅ |
| 4 | Products and stock | ✅ |
| 5 | Sales (POS) | ✅ |
| 6 | Purchases, parties, payments, expenses | ✅ |
| 7 | Dashboard, Galla Band, reports | ✅ |
| 8 | Mobile Shop Pro | ✅ |
| 9 | License, backup, security hardening | ✅ |
| 10 | Polish and release | ✅ code side — **needs a real-phone pass and a signed AAB built on your machine** |

The spec asks for each milestone to be tested on a real Android phone before
the next. The automated tests below cover the accounting and every screen,
but the manual checklist (end of this file) still has to be done on a phone.

## Setup

Needs Flutter stable (3.38 or newer) and Android Studio / Android SDK.

```bash
git clone <this repo> && cd smart-dukan
flutter pub get
flutter test               # ~110 tests, about a minute
flutter run                # phone connected with USB debugging on
```

The generated Drift code (`app_database.g.dart`) and the `android/` folder
are committed, so no code generation is needed. After changing a table:
`dart run build_runner build`, then add a migration step (see
`lib/core/db/migrations/migrations.dart`).

## Before the first pilot: create YOUR licence key

The repository ships with a placeholder public key whose private key was
thrown away, so **no one can issue codes for it**. On the laptop you will
use to sell licences:

```bash
dart run tools/license_gen.dart init      # writes tools/keys/license_private.key (git-ignored)
                                           # and updates lib/core/security/license_public_key.dart
git commit -am "Production licence public key"   # the PUBLIC key only
```

Back up `tools/keys/license_private.key` offline (USB). Never put it in Git,
WhatsApp or a cloud folder. Running `init` again invalidates every code
issued before.

Selling Mobile Shop Pro:

```bash
# Customer sends their Device Code (More → Licence and Pro packs)
dart run tools/license_gen.dart issue --device K7QM2-XPA9D-... --buyer 03001234567
# → prints the code, the smartdukan://activate?c=... link and a WhatsApp message
# → appends to tools/keys/sales_register.csv (licence id, device, buyer, date)
# New phone (transfer): issue for the new Device Code with --transfer-from <old licence id>
```

## Release build

1. Create an upload keystore and `android/key.properties` (git-ignored):
   ```
   storeFile=/path/to/upload-keystore.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
2. `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`
3. `flutter build apk --release --split-per-abi` to check the size (target < 30 MB).

Release builds use R8 shrinking, remove the INTERNET permission, disable
Android auto-backup and keep the app portrait-only.

## Architecture (spec Section 6)

```
lib/
  app/          router, providers, bootstrap (opens the encrypted DB), shell
  core/
    accounting/ posting engine, ledger queries, allocation, health check
    db/         Drift tables, migrations, encrypted opener
    security/   PIN (PBKDF2), licence (Ed25519), photo vault (AES-GCM), keystore, FLAG_SECURE
    money/      Money (integer paisa) and formatting
    pdf/ theme/ l10n/ widgets/ utils/ settings/
  features/     each with data/ application/ presentation/
    onboarding dashboard products sales purchases parties payments expenses
    cash_closing reports settings backup license pro_mobile/{imei,used_phones,repairs,qist}
tools/license_gen.dart
```

* **Money** is always integer paisa (`Money`), never `double`.
* **Every business event** runs in one DB transaction through
  `PostingService`: document + stock movements + stock balances + a balanced
  journal entry. If anything fails nothing is saved.
* **Mistakes are reversed, never deleted**: reversal documents mirror the
  journal and stock (`reverses_id`).
* **Health Check** (More → long-press *About*) runs every Section 8 invariant.

## Tests

| Area | File |
|---|---|
| Section 8 worked example | `test/core/accounting/worked_example_test.dart` |
| Every posting rule, returns, allocation, closing, reversals | `test/core/accounting/posting_rules_test.dart` |
| IMEI, repairs, qist, used phones | `test/core/accounting/pro_posting_test.dart` |
| Encryption, migrations, seeding | `test/core/db/database_test.dart` |
| Licence (valid / tampered / wrong device), PIN hashing | `test/core/security/license_test.dart` |
| Backup → wipe → restore, wrong password, tampering | `test/features/backup_test.dart` |
| Demo shop loads and reconciles | `test/features/demo_data_test.dart` |
| Excel/CSV import | `test/features/product_import_test.dart` |
| Reports vs worked example | `test/features/reports_test.dart` |
| New Sale in 3 taps, double-tap Save, Udhaar needs customer, onboarding | `test/features/sale_flow_test.dart` |
| **Every screen** in English / Roman Urdu / Urdu without errors or overflow | `test/features/all_screens_smoke_test.dart` |
| Golden screenshots Home + Sale, en/ur, light/dark | `test/goldens/` |
| 5,000 products / 20,000 sales performance | `flutter test test/perf --run-skipped --tags perf` |

Measured on a desktop CPU with the encrypted DB (indicative only):
search 3–22 ms, sale save 13 ms, year-long reports 54–494 ms, Health Check
1.2 s on 20,000 sales.

## Manual acceptance checklist (spec Section 10) — do on a real phone

- [ ] Full sale, purchase, payment and expense in airplane mode from a fresh install
- [ ] Cash, udhaar, mixed and wallet payments post correctly
- [ ] Partial payment and oldest-first allocation
- [ ] Sale return and purchase return restore stock and balances
- [ ] Carton to piece conversion
- [ ] IMEI cannot be sold twice; IMEI search shows full history
- [ ] Used phone purchase saves CNIC photos privately (screenshot blocked)
- [ ] Repair job moves through all statuses; parts deduct stock
- [ ] Qist plan generates schedule; partial instalment and overdue list work
- [ ] Galla Band difference posts to Cash Over/Short
- [ ] Cashier role cannot see cost or profit
- [ ] Kill the app mid-save: no half-saved documents after restart
- [ ] Backup, wipe app, restore: every balance identical
- [ ] 5,000 products and 20,000 sales: search and reports fast on a 3 GB phone
- [ ] Urdu mode: no clipped Nastaliq text, numbers stay LTR
- [ ] Licence: valid code unlocks Pro; tampered code rejected; restore keeps data readable without Pro

Store assets: `assets/store/icon_512.png`, `feature_graphic_base.png`; the
golden images in `test/goldens/` are a starting point for Play screenshots
(English and Urdu).
