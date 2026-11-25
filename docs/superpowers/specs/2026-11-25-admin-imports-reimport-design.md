# Reimport from `/admin/imports`

## What is asked

From the imports table, an admin replays an import with the parameters it was run with. The row's
actions become **Reimport** (primary), **Undo** (secondary, bulk standings runs only, unchanged) and
**Delete** (danger). Reimport replaces Retry.

## What the code held before this change (measured on `d8d464a`)

- `imports` stores `kind` and `label` and nothing it was run from. `Retry` was an allowlist of
  `deck` and `card_set`, offered on failed/pending rows only, and it **destroyed** the row it retried.
- `card_set` was the only kind the label could rebuild (the set code → its Limitless URL). The
  `deck` branch re-enqueued the label — the deck's *name* — as the decklist, a bug recorded in a
  comment since the field-list feature.
- `standing_list` (decklist), `limitless_standings` (source, ids, filters, archetype, row count) and
  `card_labels` (`card_label_id`) lost what their job needs.
- `bulk_cards` stores its payload in `receipt`, and replaying it is refused on purpose: the add is
  relative, so a second run adds every copy again.
- No `imports` fixture exists; tests build their rows inline.

## Decisions

1. **A new column, `imports.replay_params`** (`json`, `NOT NULL`, default `{}`), written by each of
   the five entry points with exactly the arguments its job receives beyond the ids the replay
   recreates:

   | kind | `replay_params` | job |
   |---|---|---|
   | `deck` | `decklist`, `name` | `Decks::ImportJob(decklist, user, name, import)` |
   | `card_set` | `url` | `CardSets::ImportJob(url, user, import)` |
   | `standing_list` | `standing_id`, `decklist` (and the row's `tournament_id`) | `StandingListImportJob(standing_id, decklist, user_id, import_id)` |
   | `limitless_standings` | the controller's `job_options` minus `expected_row_count` (decision 7) | `LimitlessImportJob(import_id, user_id, options)` |
   | `card_labels` | `card_label_id` | `CardLabels::ImportJob(import_id, card_label_id, user_id)` |

   Keys are Strings everywhere, writer and reader: a `json` column hands them back as Strings
   whatever was written, and `LimitlessImportJob` already reads its options with String keys.

2. **The migration backfills `card_set` rows** from their label — the one kind whose label is the
   whole job, and what Retry already relied on. Every other pre-existing row keeps `{}` and gets no
   Reimport button: what it was run from is genuinely gone.

3. **Reimport keeps the original row.** It creates a new `Import` (same kind, label, user,
   tournament and `replay_params`) and enqueues the job against it. Keeping the row keeps the
   history, the error message and — for a bulk standings run — the only receipt its Undo reads.
   A stuck pending row can still be deleted by hand.

4. **Any status may be reimported.** A completed run is the main case (re-read a set that
   Limitless has since priced, re-run a label search). A pending row is allowed so the action keeps
   what Retry offered for a stuck job; if that job is in fact still running, both run. Each job is
   safe to run twice in the sense that matters: a set import re-links, a label import writes the
   same rows, a field-list import replaces the standing's list (see decision 9), a bulk standings run de-duplicates,
   and a deck import makes a second deck — which is what "import this decklist again" means.

5. **The replay runs as the import's own user**, as Retry did: a deck import lands in that member's
   decks and their notifications stream, not the admin's.

6. **Refusals** (alert, nothing written, nothing enqueued):
   - `bulk_cards` — the existing sentence (relative add).
   - no stored parameters — "was run before its parameters were stored".
   - `card_set` while another import of the same set is pending — the guard
     `Admin::CardSetsController#import` applies, excluding the row being replayed.

7. **A bulk standings replay is how new decks of an archetype come in, so it carries no row
   count.** This is the feature's main motivation, stated by the owner: re-run the paper or online
   source of an archetype to pick up the lists Limitless has published since, without fetching the
   URL and choosing the archetype again. The first run's `expected_row_count` is therefore **not
   stored**. Kept, it would refuse every replay of a completed run: `StandingsImportPlan` plans the
   rows already written as `:skip`, so `importable_rows` shrinks to the new rows only and
   `LimitlessImportJob#verify!` raises `PlanDrifted` (`limitless_import_job.rb:216`). Without it, a
   replay imports the rows that are new and skips the rest. It stays bounded by `PlanTooLarge` (the
   plan's 300-row ceiling) and by the run's own `event_filters` and `limit_per_event`. The new
   rows land on the **new** Import's receipt, so Undo on the replay takes back only what the
   replay wrote. The event source never carried a count, so nothing changes for it. A deleted
   standing, label or archetype fails the replay through each job's own existing guard, and the
   new row reads failed with the reason.

8. **Buttons** go through the existing classes: `btn btn-primary btn-sm`, `btn btn-secondary btn-sm`,
   `btn btn-danger btn-sm`. Delete was `btn-danger btn-sm` without `btn`, so it did not share the
   others' box.

9. **A field-list replay wins over whatever the standing holds now** — owner's decision, taken
   after both reviews reproduced it: import A's list, a member's later correction B, then a replay
   of A puts A back and `StandingListImportJob` destroys B (`destroy_if_ownerless`). The replay's
   list is also a new deck with a new `key`, so a `/decks/<key>` link to the current list breaks.
   Nothing on the row shows that a newer list exists, so the confirm says it: "This replaces the
   field list the standing holds now, even one corrected since."

## Out of scope

- Editing parameters before a replay (the original form is where that happens).
- Undo for any kind but `limitless_standings`.
- Pagination of `/admin/imports` (pre-existing).
