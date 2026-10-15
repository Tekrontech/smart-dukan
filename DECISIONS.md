# DECISIONS.md

Decisions taken where the spec was unclear or could not be followed exactly
(spec Section 0, rule 6). Newest at the bottom.

## D-001 — Roman Urdu locale is `en_PK`, not `ru`
**Milestone 1.** The spec names the Roman Urdu file `app_ru.arb`. But `ru` is
the real locale code for Russian, so Flutter's built-in Material widgets
(date pickers, "Cancel"/"OK", tooltips) would show Russian text. Roman Urdu
is written in Latin script, so it uses `app_en_PK.arb` (locale `en_PK`):
our strings are Roman Urdu, and Flutter's built-in strings fall back to
English. In code it is `AppLanguage.romanUrdu`.

## D-002 — Default language is Roman Urdu
**Milestone 1.** Until onboarding (Milestone 3) lets the user pick a
language, the app starts in Roman Urdu, matching the spec's shopkeeper
vocabulary (Lena, Dena, Galla).

## D-003 — Fonts bundled (resolved in Milestone 2)
**Milestone 1** could not download fonts. **Milestone 2:** Inter (static
Regular/Medium/SemiBold/Bold), Noto Nastaliq Urdu and Noto Naskh Arabic
(Regular/Bold) are now in `assets/fonts/` with their OFL licences, and the
`fonts:` block is active.

## D-004 — Language/theme preferences are in memory for now
**Milestone 1.** Preferences live in a Riverpod notifier. Milestone 2 creates
the encrypted `app_settings` table, and they will be persisted there (no
`shared_preferences`, so everything stays in the encrypted DB).

## D-005 — Riverpod providers are hand-written in Milestone 1
**Milestone 1.** The spec lists `riverpod_generator`. Code generation
(`build_runner`) arrives in Milestone 2 together with Drift and Freezed;
adding it earlier for two providers adds setup with no benefit. New
providers from Milestone 2 onward use the generator.

## D-006 — "+ Nayi Sale" button floats above the nav bar
**Milestone 1.** With 5 tabs, a docked centre button would cover the Khata
tab. The extended "+ Nayi Sale" button floats centred above the bar and hides
on the Sale tab itself.

## D-007 — Urdu line height ×1.35
**Milestone 1.** Nastaliq glyphs are tall, so Urdu text styles use 1.35×
line height and Home grid cards are sized for it, to avoid clipped text.
Re-check on a real phone once fonts are bundled.

## D-008 — Encryption via SQLite3MultipleCiphers in SQLCipher mode
**Milestone 2.** `sqlcipher_flutter_libs` is end-of-life; `package:sqlite3`
3.x now bundles SQLite through build hooks. `pubspec.yaml` selects
`source: sqlite3mc` and `db_open.dart` sets `PRAGMA cipher='sqlcipher'`,
`legacy=4` and a raw 256-bit `hexkey`, i.e. a SQLCipher v4 compatible file.
A test proves the file has no plaintext and a wrong key fails.

## D-009 — No Freezed / riverpod_generator
**Milestone 2.** Drift already generates immutable row classes with
`copyWith`, and input objects are small `const` classes. Skipping Freezed and
riverpod_generator keeps one code generator (Drift) and faster builds.
Providers are hand-written.

## D-010 — Generated Drift code is committed
**Milestone 2.** `app_database.g.dart` is committed so the app builds with a
plain `flutter pub get`. After changing a table run
`dart run build_runner build` and commit the result.

## D-011 — "Mixed" payment = part paid now + rest udhaar
**Milestone 2.** Spec 5.3 says Mixed "shows two amount fields". It is
implemented as *paid now* (cash, bank or wallet) + *udhaar* for the rest,
so it needs a named customer like Udhaar.

## D-012 — Extra columns and tables beyond Section 7
**Milestone 2.** Needed to make every rule exact and testable:
- `stock_movements.value_change`, `stock_key`; `stock_balances.stock_key`
  (variant_id is nullable, so a text key gives a unique bucket).
- `sales.gross`, `sales.markup`; `sale_items.unit_id`, `unit_qty`,
  `description`, `net_amount`, `tax_amount`, `cost_total` (exact COGS, so
  returns reverse to the paisa without rounding drift).
- `purchases.extra_cost` (freight/tax into cost), `purchase_items.net_cost`.
- Separate `sale_returns`, `sale_return_items`, `purchase_returns`,
  `purchase_return_items`, `stock_adjustments` documents.
- `payment_allocations.source_type` (payment or return credit), `payments.ref_type/ref_id`
  and `journal_lines.ref_type/ref_id` (repair job / qist plan balances),
  `journal_entries.reverses_id`.
- `doc_counters` for gap-free numbers; `businesses.go_live_date`.

## D-013 — How reversals are stored
**Milestone 2.** A reversal inserts a mirror document row
(`status = reversal`, `reverses_id` → original) and mirror journal entries
and stock movements; the original becomes `status = reversed`. Reversed
invoices keep their number; the sequence check ignores mirror rows.
A sale with returns, or a qist sale with collections, cannot be reversed
(return/cancel instead). A purchase whose stock is already sold cannot be
reversed (use a purchase return).

## D-014 — Qist scope in V1
**Milestone 2.** A qist sale carries no tax or delivery. Cancellation with
device take-back handles one device (the first line), which is how phones
are sold on qist. Write-off of an active plan clears unearned markup first
(Dr DEFERRED_MARKUP) and books only the rest as BAD_DEBT.

## D-015 — Opening entries use OPENING_EQUITY
**Milestone 2.** Section 8 says Owner Capital, 8.1 says OPENING_EQUITY and
"overrides the summary table", so all opening balances credit/debit
OPENING_EQUITY on the go-live date.

## D-016 — Tax and delivery on returns
**Milestone 2.** The tax share of a return debits SALES_TAX_PAYABLE (not
SALES_RETURNS) so tax payable stays right. Delivery charges are not
refunded by a goods return.

## D-017 — Inventory account always equals stock value
**Milestone 2.** Every stock movement posts its own INVENTORY line inside
the posting engine, so the INVENTORY account balance always equals
Σ stock_balances.value. This is an extra Health Check invariant.

## D-018 — JazzCash and Easypaisa share the WALLET account
**Milestone 2.** The spec has one WALLET system account; the payment row
keeps the exact method for reports. Bank transfers use BANK.

## D-019 — One Galla Band per day
**Milestone 2.** A day can be closed once. Expected cash = the CASH account
balance at closing time. A second closing the same day is refused.

## D-020 — Advances and return credits are used up automatically
**Milestone 2.** Unallocated payments and return amounts kept as credit are
matched oldest-first to open invoices whenever a sale/purchase with a due is
saved or a payment is reversed. This only affects the open-invoice list;
balances always come from the journal.

## D-021 — Repairs
**Milestone 2.** Repair parts use the COGS account. A repair job is not a
posted document itself; its advances, parts and delivery are, and payments
can be reversed. Parts cannot be IMEI items. A closed job (delivered /
returned) accepts payments and refunds only.

## D-022 — Used-phone purchase is its own document
**Milestone 2.** It posts Dr Inventory / Cr Cash and creates an in-stock IMEI
unit; it does not create a supplier purchase bill.

## D-023 — PIN is 4 digits in the app
**Milestone 3.** Spec 5.1 says "Set a 4-digit PIN", Section 9 allows 4–6.
The PIN pad auto-submits after 4 digits; `PinService` accepts 4–6 so longer
PINs can be added later without a data change. Hash: PBKDF2-SHA256,
30,000 iterations, random 16-byte salt, run off the UI thread. Five wrong
tries lock the pad for 30 seconds.

## D-024 — Undo right after a sale needs no owner PIN
**Milestone 5.** Section 9 requires the owner PIN for reversals, but the
5-second Undo snackbar (Section 4) is for the cashier fixing a mis-tap.
Undo still creates a reversal (never a delete) and is audit-logged; any
later reversal asks for the owner PIN.

## D-025 — "Heavy reports run in an isolate"
**Milestone 7.** The database runs on its own background isolate
(`NativeDatabase.createInBackground`) and every report aggregates in SQL,
so the UI isolate never does heavy work. Measured: year-long reports with
20,000 sales finish in under 0.5 s on desktop.

## D-026 — Stock-value and dues reports are snapshots
**Milestone 7.** Stock value, low stock, customer ageing and supplier dues
show the position *now* and ignore the date range. Customer ageing buckets
open invoices by age; opening balances and amounts not tied to an open
invoice go in "Other".

## D-027 — Licence key placeholder
**Milestone 9.** The committed public key was generated during development
and its private key destroyed. The owner must run
`dart run tools/license_gen.dart init` before the pilot (see README).

## D-028 — Install ID vs. lost secure storage
**Milestone 9.** The spec's "secure storage lost but DB intact" case cannot
fully happen: the database key itself lives in secure storage, so if
secure storage is wiped the encrypted DB cannot be opened. The app then
shows a "restore your backup" screen (`StartupErrorApp`). The install ID is
still mirrored in the DB, and a mismatch between the two shows the
re-activate notice on the licence screen.

## D-029 — Printing in V1 uses the system print dialog
**Milestone 5.** Receipts are 80 mm PDFs printed through Android's print
service (and shared as PDF or PNG). Direct Bluetooth thermal printing is
V1.1 in the spec.

## D-030 — Google Play billing stays off
**Milestone 9.** Only manual JazzCash/Easypaisa activation codes are
implemented. A `play_billing_enabled` setting key is reserved for the
feature flag; no billing library is included until Play policy is checked.

## D-031 — Pro gating
**Milestone 8.** Without Pro, creating new qist sales, used-phone purchases
and repair jobs, and opening Pro reports, shows the "Get Pro" sheet.
Existing Pro records, IMEI search and all exports stay available
(spec Section 2: never lock a user out of their data).

## D-032 — Android build not verified in the build environment
**Milestone 10.** The AI build environment could not reach Google's Android
SDK servers, so `flutter build appbundle` was not run there. Dart code is
fully analysed and tested; the first Gradle build must be done on the
owner's machine (README "Release build").

## D-033 — CNIC retention runs at start-up
**Milestone 9.** On each app start, seller identity data (CNIC number and
photos) of phones sold more than the retention period ago (default 12
months) is overwritten and deleted; the purchase record stays. Owners can
also delete it on request from the used-phone screen. Every CNIC view and
deletion is audit-logged without the CNIC itself.
