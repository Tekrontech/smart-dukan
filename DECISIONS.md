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

## D-003 — Fonts are declared but not yet bundled
**Milestone 1.** The build machine could not download font files. The
`fonts:` block in `pubspec.yaml` is commented out and the app uses the system
font until the TTFs are added. See `assets/fonts/README.md`. Text styles
already reference Inter / Noto Nastaliq Urdu / Noto Naskh Arabic, so adding
the files and uncommenting the block is the only step needed.

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
