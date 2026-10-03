# Standings sheet filters — plan

Spec: `docs/superpowers/specs/2026-10-03-standings-sheet-filters-design.md`.
One lane (server + view are ~150 lines together; a second lane would cost more than it returns).

## Contract

- Params: `player`, `archetype` (slug), `division`. Each read with `params[:x].to_s` (non-scalar
  shapes become `""`-ish garbage and are ignored).
- `TournamentStanding.player_matching(query)` — scope, `LIKE '%…%' ESCAPE '\'` on
  `tournament_standings.player_name_normalized`, query folded with `squish.downcase` and
  `sanitize_sql_like`.
- `TournamentsController#load_standings_page` builds:
  - `@archetype_options` — `Archetype.where(id: scope.select(:archetype_id)).order(:name)`, loaded
    (needs `name`, `slug` only).
  - `@division_options` — `scope.distinct.pluck(:division)` sorted by `DIVISIONS.index`.
  - `@sheet_filters` — `{ player:, archetype:, division: }`, each kept only if valid: archetype
    must be among `@archetype_options`' slugs, division among `@division_options`.
  - filtered scope → count/pages/clamp/page, as today.
- `Tournaments::ShowView` new keywords: `sheet_filters: {}`, `archetype_options: []`,
  `division_options: []`. `SHEET_FRAME_ID = "tournament_sheet"`.
- `Ui::Pagination` gains `turbo_frame:` (adds `data-turbo-frame`).

## Steps (TDD)

1. Controller tests (red): player substring case-insensitive; `%` literal; archetype exact
   excludes a child; division; combination; unknown slug/division ignored; `?player[]=x` 200;
   filtered pager count and hrefs carry filters; out-of-range page clamps to filtered pages;
   empty filtered result message vs unfiltered message; no filter bar on empty event; division
   select absent with a single division; options in name / DIVISIONS order; flat query count
   for a filtered request.
2. Model scope + controller.
3. View: filter form (`card-filter` controller, `data-turbo-frame` = frame id, `turbo_action`
   replace), Clear link (`card_filter_target: clear`), frame `target: "_top"`, pager with
   `turbo_frame:`.
4. CSS: reuse `.deck-filters` / `.deck-filter-select` / `.deck-filter-search`.
5. System test (both viewports): typing a player name narrows rows without losing the field's
   focus/value; selecting an archetype narrows; a row's Edit link from the filtered sheet opens the
   edit page (no "Content missing"); pager inside the frame keeps filters.
6. Docs: `docs/architecture/tournaments-and-standings.md` (frame paragraph rewritten),
   `TournamentsController` rate-limit comment, `docs/architecture/public-surface.md` show line.
