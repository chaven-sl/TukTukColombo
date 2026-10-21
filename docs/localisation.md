# Localisation

## Workflow

1. Player-facing text uses translation **keys** only: `tr("UI_SCORE")`, never literal strings in gameplay/UI code (debug overlay excepted).
2. Add every new key to `locale/en.po`, `locale/si.po`, `locale/ta.po` (empty `msgstr` in si/ta is allowed while untranslated).
3. Godot loads the three `.po` files from `internationalization/locale/translations`; `internationalization/locale/fallback = en`, so an empty Sinhala/Tamil string shows English.
4. Locale is stored in the save (`settings.locale`) and applied by `GameState` at start (`TranslationServer.set_locale`).
5. `tests/unit/test_project_setup.gd` asserts all English UI keys resolve, si/ta load, and fallback works.

Current keys: `UI_SCORE UI_SPEED UI_KMH UI_COMBO UI_COMBO_LOST UI_CLOSE_CALL UI_TIGHT_GAP UI_ONCOMING UI_PAUSED UI_PAUSE_HINT PASSENGER_RUSHED_NAME PASSENGER_CAREFUL_NAME PASSENGER_THRILL_SEEKER_NAME`.

## Sinhala and Tamil status

- English complete.
- Sinhala: `UI_SCORE = ලකුණු`, `UI_SPEED = වේගය` as **test strings only**; everything else falls back to English.
- Tamil: `UI_SCORE = மதிப்பெண்`, `UI_SPEED = வேகம்` as **test strings only**.
- All strings need native-speaker review. Game terms (close call, tight gap, combo) need culturally natural phrasing, which may be colloquial or English loanwords as used on Colombo streets.

## Font requirements (blocking for release, not for v0.01)

- Godot's default font does not include Sinhala or Tamil glyphs, so these locales render boxes ("tofu") today. **No font has been added.** We did not download unvetted fonts.
- Needed: an open-licensed (SIL OFL 1.1) family with Sinhala + Tamil + Latin, e.g. the Noto Sans Sinhala / Noto Sans Tamil families (OFL). Before adding: confirm licence text, ship the OFL licence file, subset if size matters, and set it as a theme fallback font.
- Both scripts need **complex text shaping** (conjuncts, vowel signs, reordering). Godot 4's TextServer (HarfBuzz/ICU) supports this when the font has the OpenType tables. Keep the default `TextServerAdvanced`.

## Complex-script testing requirement

Before shipping si/ta: on device, verify conjuncts and vowel-sign ordering in every UI string, line height and clipping in the HUD popups (Sinhala/Tamil glyphs are taller), text width in the combo label, and number formatting next to script text. Record screenshots per locale in a test log.
