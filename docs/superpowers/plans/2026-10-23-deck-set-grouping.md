# Deck page grouped by set — plan

Spec: `docs/superpowers/specs/2026-10-23-deck-set-grouping-design.md`.

One lane: the change is a service, one component, a controller helper, two small Stimulus edits and
CSS — splitting it would cost more coordination than it saves.

## Contract

- URL parameter `group`; `"set"` selects the set view, anything else (or absent) the type view.
- `DecksController#deck_grouping` (private) → `:set` or `:type`, read by `owner_show` and `edit`,
  exposed as `@group`; `show.html.erb` passes `group: @group || :type` to `Decks::ShowView`.
- `Decks::ShowView.new(..., group: :type)`; `Decks::ShowView::GROUPINGS = [[:type, "Type"], [:set, "Set"]]`.
- `Decks::SetGroups.call(deck_cards)` → `Array<Decks::SetGroups::Section>`, `Section =
  Struct(:card_set, :code, :deck_cards)` with `#label` (`"Name (CODE)"` or `"CODE"`) and
  `#copies`; sections and their `deck_cards` already ordered.
- `Decks::SetGroups.number_key(set_number)` — the in-section sort key.
- `Decks::HeaderFrame.new(deck:, editing:, group: nil)` — Cancel link carries `group:`.
- `Decks::ActionsDropdown.new(..., group: nil)` — Edit link carries `group:`.
- DOM: `.deck-show-main[data-deck-group="set"]` in set mode; `.deck-group-modes` /
  `.deck-group-mode` / `.deck-group-mode--current`; set sections are `.deck-section.deck-set-section`
  with `data-set-code`; `data-deck-totals-target="sectionNoun"` on the heading's noun.
- `deck_totals_controller.js`: re-pluralises `sectionNoun` when present.
- `printing_picker_controller.js`: after a successful swap inside `[data-deck-group="set"]`,
  `Turbo.visit(window.location.href, { action: "replace" })`.

## Steps (TDD)

1. `test/services/decks/set_groups_test.rb` — order of sections (release desc, undated after
   dated, unlinked last alphabetical, unlinked folded into a present set of the same code), order
   inside a section (numeric, `GG` after numerics, `GG2 < GG10`), label, copies.
   Then `app/services/decks/set_groups.rb`.
2. `test/controllers/decks_controller_test.rb` — `?group=set` renders set sections with headings
   in order; default and `?group=junk` render the type view unchanged (no set sections); the
   mode links and `aria-current`; `edit` honours `group`; Edit/Cancel links carry it; set-mode
   query count flat in decklist size; public page ignores `group`.
   Then controller + `ShowView` + `HeaderFrame` + `ActionsDropdown`.
3. `test/system/deck_set_grouping_test.rb` — switch to Set, `+` updates the set heading count and
   noun, a printing swap in set mode moves the row to its new set section.
   Then the two Stimulus edits and CSS.
4. Gate list, sabotage, geometry of the mode control at 390/500 and 1400.
