# Plan: standings import from one Limitless URL

Spec: `docs/superpowers/specs/2026-10-03-standings-import-url-design.md`.

## Contract

- New service `Tournaments::LimitlessUrl < ApplicationService`, `call(text)` returns
  `Tournaments::LimitlessUrl::Parsed = Data.define(:source, :deck_id, :tournament_id, :slug, :rotation, :set)`
  (unused members nil). It raises `Tournaments::LimitlessUrl::ParseError` with an admin-readable message.
  `source` is one of `"paper"`, `Tournaments::LimitlessImportJob::ONLINE_SOURCE`, `EVENT_SOURCE`.
- The form param is `url`. **Preview reads it whenever the key is present** (the new form always
  sends it), parses it, and writes the same ivars `read_form_params` writes today (`@source`,
  `@deck_id`, `@slug`, `@rotation`, `@set`, `@tournament_id`). A `ParseError` is a refusal that
  re-renders the form before any fetch, through the existing `refusal` chain (source refusal first).
- With no `url` key at all (the confirm forms' POST to `#create`, and a preview bookmarked before
  this change), the individual params are read exactly as today.
- `Admin::StandingsImports::Form` drops `source:`, `deck_id:`, `slug:`, `rotation:`, `set:`,
  `tournament_id:` and takes `url:`. It renders one text input `name="url" id="url"`, labelled
  "Limitless URL". `NewView` passes `url:` through and still passes the parsed values to
  `PlanTable` / `EventConfirmForm`, whose hidden fields do not change.

## Steps

1. `test/services/tournaments/limitless_url_test.rb`, red then green:
   - the three user URLs give the expected `Parsed`;
   - paper `/decks/284`, trailing slash, `http`, `www.`, fragment;
   - event sub-pages `/JR`, `/decklists`;
   - online trailing slash `/decks/dragapult-ex/?…`;
   - refusals: blank, not a URL, foreign host, unknown path, paper `?variant=3`,
     online missing each of format/rotation/set, online `format=expanded`;
   - an extracted value that fails a controller guard (e.g. uppercase slug) is still *extracted*.
     Validation is the controller's job, and the controller test asserts that refusal.
2. `app/services/tournaments/limitless_url.rb`.
3. Controller: `read_form_params` branches on `params.key?(:url)`, and `source_refusal` returns
   `@url_error` first. Controller tests: preview by `url` for each source (asserting the fetched
   URL), a refused URL fetches nothing, a variant URL fetches nothing, a URL whose slug fails
   `SLUG_RE` is refused by that guard. Then the confirm form, rendered from a URL preview, carries
   the parsed hidden values. Update `assert_select "input#deck_id"` → `input#url`.
4. Form/NewView: one URL field. Update the three system tests to `fill_in "Limitless URL"`.
5. CLAUDE.md / `docs/architecture/limitless-imports.md`: say the screen takes a URL and why the
   three refusals exist.
