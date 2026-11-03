# Plan: admin card from scratch

Spec: `docs/superpowers/specs/2026-11-03-admin-card-from-scratch-design.md`.

## Frozen contract

- `Card::STAGES = ["Basic", "Stage 1", "Stage 2", "VSTAR", "VMAX", "EX", "BREAK"]`,
  `Card::SUBTYPES = ["Item", "Tool", "Supporter", "Stadium", "Special Energy", "Basic Energy"]`.
- `Cards::ManualWriter < ApplicationService`, `ATTACK_SLOTS = 3`, `ABILITY_SLOTS = 2`.
  `Cards::ManualWriter.call(card, attributes:, attacks:, abilities:)` → `true` / `false`;
  on `false`, `card.errors` holds every reason. `attributes` is a permitted Hash of card columns;
  `attacks` an Array of Hashes with String keys `"name" "cost" "damage" "effect"`, in slot order;
  `abilities` the same with `"name" "effect"`.
  - Strips every value; a slot whose values are all blank is skipped; a slot with a value but a
    blank name adds `errors[:base]` "Attack N needs a name" / "Ability N needs a name" (N 1-based,
    the slot's own number).
  - Kept slots get `position` 0, 1, … in order; blank `damage`/`effect` → nil; blank `cost` on a
    kept attack → `"0"`.
  - `pokemon_subtype = PokemonSubtype.for_card_name(name)` when `card_type == "Pokémon"`, else nil.
  - Inside `serialized_transaction`: on a persisted card destroy its attacks and abilities, build
    the kept slots, bump `updated_at` on a persisted card, validate, add slot errors, roll back
    unless both are clean, else `save!` once. After commit, `Card.forget_filter_values`.
- Routes: inside `namespace :admin` → `resources :card_sets do … resources :cards, only: %i[new create] end`.
  Helpers `new_admin_card_set_card_path(set)`, `admin_card_set_cards_path(set)`.
- `Admin::CardsController`
  - `before_action :set_card_set, only: %i[new create]` (`CardSet.find(params[:card_set_id])`).
  - `new`: `@card = @card_set.cards.new(set_name: @card_set.code)`.
  - `create`: `@card = @card_set.cards.new(set_full_name: @card_set.name)`, writer with
    `card_params.except(:card_set_id)`; success → `redirect_to admin_card_path(@card), notice: "Card created."`;
    failure → `render :new, status: :unprocessable_entity`.
  - `update`: writer; notice `"Card updated."`, plus — when `@card.saved_change_to_fingerprint?` —
    ` Its fingerprint moved from OLD to NEW: run bin/rails card_labels:resync_fingerprints and bin/rails archetypes:resync_fingerprints.`
  - `card_params` permits: `name card_type stage subtype evolves_from hp type_symbol weakness
    resistance retreat_cost rarity regulation_mark set_name set_number card_set_id artist image_url effect`.
  - Slot params: `params[:card][:attacks]` / `[:abilities]` are Hashes keyed `"0"`, `"1"`, …,
    each permitted to its keys, converted to the Arrays above ordered by integer key.
  - The controller hands the view `@attacks` / `@abilities` (Arrays of String-keyed Hashes): from
    the card's attacks/abilities on `new`/`edit`, from the submitted slots on a refused write.
- Views (`phlex-architecture` skill)
  - `Admin::Cards::Form.new(card:, attacks:, abilities:, url:, submit_label:, cancel_path:)`.
    Renders `max(ATTACK_SLOTS, attacks.size)` attack slots and `max(ABILITY_SLOTS, abilities.size)`
    ability slots, field names exactly `card[attacks][<i>][name|cost|damage|effect]` and
    `card[abilities][<i>][name|effect]` — **String** `name:` values. Stage/subtype are selects over
    the constants with a blank, plus the card's current value when it is outside them. The card-set
    select is rendered only for a persisted card.
  - `Admin::Cards::NewView.new(card:, card_set:, attacks:, abilities:)`, title
    `"New card in #{card_set.name}"`, form posting to `admin_card_set_cards_path(card_set)`, submit
    `"Create Card"`, cancel to the set page. `EditView` gains `attacks:, abilities:`; submit `"Update Card"`.
  - `Admin::CardSets::ShowView`: a `"New card"` link (`btn btn-secondary`) to
    `new_admin_card_set_card_path(@card_set)` in `.admin-header-actions`, first.
  - `app/views/admin/cards/new.html.erb` one-liner.

## Lanes

One lane. The controller's round-trip tests need the form, and the form needs the controller's
slot arrays, so a server/view split would leave each half untestable alone; SQLite also allows one
test runner per worktree. One `ship-lane` agent implements everything below, running tests itself.

## Tests (TDD order)

`test/services/cards/manual_writer_test.rb`
1. A Pokémon created from slots gets the fingerprint of the same card built the documented way
   (`Card.new` + `attacks.build` + one `save`) — and differs from the same card without attacks.
2. Blank cost on a named attack is stored `"0"`; blank damage/effect nil; values stripped.
3. Positions compact over skipped slots (slot 1 blank, slot 2 filled → position 0).
4. An all-blank slot writes nothing; a slot with only an effect refuses the card, names the slot
   number, and writes no card, attack or ability.
5. Update replaces attacks and abilities; a refused update (Pokémon with blank HP) leaves the
   database rows — card columns, attacks, abilities — exactly as before.
6. `pokemon_subtype`: "Foo ex" → "Pokémon ex"; a Trainer gets nil.
7. Success deletes `Card::FILTER_VALUES_CACHE_KEY`; a refusal leaves it.
8. An update changing only an attack's effect moves `updated_at`.
9. A Trainer with an attack slot (Technical Machine) keeps the attack.

`test/controllers/admin/cards_controller_test.rb`
10. `GET new` pre-fills `card[set_name]` with the set code, renders 3+2 slots, no card-set select.
11. `POST create` built by **harvesting the rendered form** (field names and values from
    `GET new`, then filled) creates the card in the URL's set with `set_full_name` = set name; a
    posted `card_set_id` naming another set is ignored.
12. Refused create → 422, `.form-errors`, typed slot values re-rendered, no card.
13. Update notice carries the resync sentence when the fingerprint moved, and not otherwise.
14. Edit of a card holding 4 attacks renders 4 attack slots and an update round-trip keeps all 4.
15. Edit of a card whose stage is outside `Card::STAGES` keeps it selected.

`test/components/admin/card_sets/show_view_test.rb` (or the controller test above if none exists)
16. The set page links to `new_admin_card_set_card_path(set)`.

`test/system/admin_card_create_test.rb`
17. Admin opens a set page, clicks **New card**, fills a Pokémon with one attack, submits, lands
    on the card's admin page, and the card's public page shows the attack — both viewports.

## Would stay green — tests the plan-adversary pass added (all mandatory)

Fixture Pokémon carry fake fingerprints (`honedge_fp`, …) and `abilities.yml` is empty, and the
test cache is `:null_store`; each test below exists because the matching plan test above would
pass against a wrong implementation.

18. **Settle first**: any test about a fingerprint or `updated_at` writes the card through the writer
    once, then `travel 1.minute`, then acts. Effect-only attack edit → fingerprint unchanged (sanity)
    and `updated_at` moved.
19. Resync notice, settled card: HP-only edit → exact sentence with the OLD value captured before the
    PATCH and the NEW one read after; rarity-only edit → exactly `"Card updated."`.
20. Update fingerprint is computed from the replacement attacks: equals a reference card built the
    documented way with the new attack.
21. Edit round-trip of a card with one ability keeps it (`pluck(:name, :effect)`); a card with 3
    abilities renders `card[abilities][2][name]` and keeps all 3.
22. A card with 1 attack renders exactly 3 attack-name inputs, the first filled, two empty.
23. Refused create with slot 0 blank and slot 1 effect-only → 422, "Attack 2 needs a name", the
    typed effect re-rendered in `card[attacks][1][effect]` and slot 0 empty.
24. Slot numbering: slot 0 valid, slot 1 blank, slot 2 effect-only → `errors[:base] == ["Attack 3 needs a name"]`.
25. Cost-only and damage-only slots refuse ("Attack 1 needs a name"); ability slot 1 effect-only
    → "Ability 2 needs a name"; an all-whitespace slot is skipped and the write succeeds.
26. Blank HP plus an effect-only slot → both messages in `full_messages`.
27. Slot-only refusal on update (valid columns) rolls back: old attacks and columns intact.
28. `pokemon_subtype`: "Foo ex" Pokémon updated to Trainer → nil; "Foo" renamed "Foo ex" → Pokémon ex.
29. Cache: swap in `ActiveSupport::Cache::MemoryStore` (pattern: `test/services/card_sets/importer_test.rb:128`);
    key gone after success, still there after a refusal; `forget_filter_values` sees the caller's
    `open_transactions` count (runs after commit).
30. Slot hashes ordered by integer key: `{"10"=>B, "2"=>A}` → positions A, B.
31. Harvested create filling every permitted field asserts each column; PATCH on edit for
    `evolves_from`, `weakness`, `regulation_mark`, `effect`.
32. Stage/subtype selects: one option per constant, in-list current value selected (stage Basic,
    subtype Special Energy), out-of-list subtype kept selected.
33. Model test: `Card::STAGES` includes "BREAK", `Card::SUBTYPES` includes "Basic Energy".
34. Edit renders `select[name='card[card_set_id]']`; a PATCH with another set's id moves it.
35. NewView h1 "New card in <set>", submit "Create Card", Cancel → set page, form action = nested
    create URL, method post; EditView submit "Update Card", Cancel → card page.
36. "New card" is `.admin-header-actions > :first-child`, `.btn.btn-secondary`, href nested new.
37. Routing: `/admin/card_sets/1/cards/1/edit` and `GET /admin/card_sets/1/cards` are not routable.
