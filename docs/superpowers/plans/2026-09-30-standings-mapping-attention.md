# Plan — standings mapping attention and inline archetype creation

Spec: `docs/superpowers/specs/2026-09-30-standings-mapping-attention-design.md`.
Single lane: the change is one service, one component, one Stimulus controller, CSS and tests.

## Frozen contract

- `Tournaments::ArchetypeProposer::Proposal` gains `suggested_cards` (Array<Card>, 0..2, primary
  first). Every `Proposal.new` in the proposer passes it; readers treat nil as `[]` (test helpers
  build proposals without it).
- The proposer resolves the list **once** (`resolved_cards`) for both `fingerprints` and
  `suggested_cards`, and preloads `pokemon_subtype` on the resolved cards in one query.
- `Ui::DataTable#row(**attrs, &block)` — merges a caller `class:` into `data-table-row`.
- `Admin::StandingsImports::MappingTable`:
  - `ATTENTION = { decide: 0, check: 1, confirmed: 2 }`; `attention(line)` →
    `:confirmed` if `line.confirmed`, `:check` if `line.selected_archetype`, else `:decide`.
  - Rows sorted by `[ATTENTION[attention], original index]`.
  - Row classes `standings-import-mapping standings-import-mapping--decide|--check|--confirmed`.
  - Badges: confirmed `badge-success`, check `badge-warning`, decide `badge-danger` (the error
    message too).
  - Summary `p.standings-import-mapping-summary`: "N to decide · N proposals to check · N confirmed
    earlier", groups at zero omitted.
  - Archetype cell: one wrapper `div.standings-import-mapping-choice` holding the hidden label, the
    select (`data-mapping-archetype-target="select"`), the "+ New archetype" button and the hidden
    create section.
  - Create section: two `Ui::CardSelect` (block form, `card-select` controller) whose hidden inputs
    carry `mapping_archetype_target: primaryId|secondaryId` and the suggested card id as `value`,
    and whose text inputs carry `Card#printing_label` of the suggestion. **No `name` on any input
    in the section.**
- Stimulus `mapping-archetype` on each row: `toggle`, `create`, `swallowEnter`, `answered`.
  `create` posts `{primary_card_id, secondary_card_id}` to `/api/archetypes` via `requestJson`,
  inserts `<option>` (name order) into every `[data-mapping-archetype-target=select]` lacking that
  value, selects it on this row, runs `answered`, hides the section. `answered` toggles
  `standings-import-mapping--answered` on the row when its select is non-empty.

## Tests

1. Proposer `suggested_cards`: name-matched Pokémon beat a rule-box tech (Beedrill case); two-token
   cover beats one-token rule-box (Honchkrow/Mewtwo); a card consumes all tokens it covers
   (Cynthia's Garchomp, no Gabite); same-token tie resolved by notability, one card only
   (Mega Greninja ex over Greninja ex); two names → primary in name order (Okidogi, Barbaracle);
   no match → `[]`; Trainer/Energy never suggested even when name-matched (Basic Box / Basic Energy);
   unresolved list → `[]`.
2. Component: sort order Decide → Check → Confirmed, stable within; row modifier classes; badge
   classes; summary counts; prefilled hidden value = suggested card id and printing label; no input
   inside `.standings-import-mapping-create` has a `name`; every line (confirmed included) has the
   New archetype button.
3. Controller: the preview's lead line for an unmapped deck carries a prefill from its real list
   (end-to-end through the proposer, not a stub).
4. System (both viewports): on a no-candidate line, open the section, see the prefill, Create &
   select → the new archetype is selected on that line and present in another line's select, row
   gets `--answered`; Enter in the card search does not submit; submit persists the mapping.
5. Geometry: desktop 1400 and mobile, no horizontal overflow with the section open.
