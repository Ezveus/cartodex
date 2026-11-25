# Plan — Reimport from `/admin/imports`

Spec: `docs/superpowers/specs/2026-11-25-admin-imports-reimport-design.md`.

## Frozen contract

- Column `imports.replay_params` — `json`, `null: false`, `default: {}`. String keys.
- `Import::REPLAYABLE_KINDS = %w[deck card_set standing_list limitless_standings card_labels]`.
- `Import#replayable?` — `REPLAYABLE_KINDS.include?(kind) && replay_params.present?`.
- `Imports::Replayer.call(import)` (an `ApplicationService`) → the new, persisted `Import`; raises
  `Imports::Replayer::Refused` (message = the admin-facing sentence) and writes nothing.
  Called from `Admin::` as `::Imports::Replayer`: `Admin::Imports` is the Phlex namespace of the
  index view, and the bare constant would resolve to it first.
- Route `post :reimport, on: :member` replaces `post :retry`; action `Admin::ImportsController#reimport`.
  Notice `"Reimported as import ##{new.id}."`; refusals redirect with `alert:`.

## Steps

1. **Migration** `AddReplayParamsToImports`: `add_column :imports, :replay_params, :json, null: false,
   default: {}`, then backfill `card_set` rows in SQL:
   `UPDATE imports SET replay_params = json_object('url', 'https://limitlesstcg.com/cards/' || label) WHERE kind = 'card_set'`.
   Down: `remove_column`.
2. **Model** — constant and `replayable?`; update the KINDS comment (no more "retryable").
3. **Writers** store `replay_params`:
   - `Api::DecksController#import` → `{ "decklist" => params[:decklist].to_s, "name" => params[:name] }`
   - `Admin::CardSetsController#import` → `{ "url" => url }`
   - `Tournaments::StandingsController#enqueue_list_import` → `{ "standing_id" => @standing.id, "decklist" => decklist }`
   - `Admin::StandingsImportsController#create` → `job_options.except("expected_row_count")`
   - `Admin::CardLabelsController#import` → `{ "card_label_id" => @card_label.id }`
4. **`Imports::Replayer`** — refusals in order: `bulk_cards` (the existing relative-add sentence),
   not replayable (`"Import ##{id} was run before its parameters were stored, so it cannot be
   reimported — run it again from where it started."`), `card_set` with another pending import of
   the same label (`where.not(id: import.id)`). Then `import.user.imports.create!(kind:, label:,
   tournament:, replay_params:)` and a `case` on kind with an `else raise` enqueuing:
   - deck → `Decks::ImportJob.perform_later(p["decklist"], user, p["name"], new)`
   - card_set → `CardSets::ImportJob.perform_later(p["url"], user, new)`
   - standing_list → `Tournaments::StandingListImportJob.perform_later(p["standing_id"], p["decklist"], user.id, new.id)`
   - limitless_standings → `Tournaments::LimitlessImportJob.perform_later(new.id, user.id, p)`
   - card_labels → `CardLabels::ImportJob.perform_later(new.id, p["card_label_id"], user.id)`
   The original row is never touched.
5. **Controller** — drop `retry`, `RETRYABLE_KINDS`, `UNRETRYABLE_REASONS`, `unretryable_reason`;
   add `reimport`. Update stale `#retry` references in comments (jobs, standings controller, docs/architecture).
6. **View** — `actions_cell`: Reimport (`btn btn-primary btn-sm`, when `imp.replayable?`, confirm
   names the label and the user it runs as; for `deck` it says a second deck is added), Undo
   (unchanged, `btn btn-secondary btn-sm`), Delete (`btn btn-danger btn-sm`).
7. **Tests** — see the adversary list below; replace the Retry tests.
8. **Docs** — CLAUDE.md (`imports.replay_params`, Reimport), `docs/architecture/limitless-imports.md`
   (bulk replay carries no row count).

## Tests the adversary asked for

| Decision the suite would not have noticed | Test |
|---|---|
| Each writer stores the right `replay_params` | one assertion each in `api/decks`, `admin/card_sets` (new file), `admin/card_labels`, `tournaments/standings`, and the three confirm tests of `admin/standings_imports` (`expected_row_count` absent) |
| The replay reads String keys and passes each job its arguments in order | `Imports::ReplayerTest` — one `args:` assertion per kind, a deck whose decklist differs from its label |
| The replay runs as the import's owner | every `ReplayerTest` row belongs to `users(:two)`; the controller test signs in `users(:one)` |
| The original is kept, the copy carries kind, label, tournament, params | `ReplayerTest` "the replay is a new pending row…", the field-list test for `tournament` |
| Any status is replayable | completed rows in `ReplayerTest` and the controller test |
| Refusals write and enqueue nothing | `assert_refused` wraps both, for bulk_cards, no params, and the set guard |
| The set guard excludes the row itself, spans users, reads only pending card-set rows of that set | three `ReplayerTest` cases |
| `REPLAYABLE_KINDS` leaves bulk_cards out | `ImportTest` with params on a bulk_cards row |
| A kind with no branch writes nothing | `ReplayerTest` "a kind with no replay written…" |
| The migration backfill | `ImportTest` runs `backfill_card_sets` |
| Buttons: which rows, which class, which order, whose email in the confirm | `Admin::ImportsControllerTest` actions-cell test |
| A replay of a completed bulk run imports only what is new, onto its own receipt | `LimitlessImportJobTest` "a replay of a completed run…" (page without one row, then with it) |
