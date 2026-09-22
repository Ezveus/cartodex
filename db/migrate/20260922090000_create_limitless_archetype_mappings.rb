class CreateLimitlessArchetypeMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :limitless_archetype_mappings do |t|
      # The deck's own reference on Limitless: the /decks/<id> of the results page, with the
      # ?variant=<n> it carries when the deck is a variant of another. Keyed on the reference and
      # never on the display name, because Limitless renames a deck as a metagame settles while the
      # reference stays put — and because eight references on one measured event are variants of a
      # shared base id, so a key that dropped the variant would file four different decks as one.
      t.integer :limitless_deck_id, null: false
      t.integer :limitless_variant
      # What the confirmation screen prints so an admin recognises the deck. Never a key: a rename
      # on Limitless updates it and moves nothing.
      t.string :label, null: false
      t.references :archetype, null: false, foreign_key: true

      t.timestamps
    end

    # Two partial indexes rather than one on the pair, the same split
    # index_tournament_entries_on_tournament_and_profile makes: SQLite treats NULLs as distinct, so
    # a single (deck_id, variant) index never sees two confirmations of the *base* deck collide and
    # one deck accumulates a mapping row per confirmation. The trap Archetype's old
    # (primary_pokemon_id, secondary_pokemon_id) index fell into.
    add_index :limitless_archetype_mappings, [ :limitless_deck_id, :limitless_variant ],
      name: "index_limitless_mappings_on_deck_and_variant",
      unique: true, where: "limitless_variant IS NOT NULL"
    add_index :limitless_archetype_mappings, :limitless_deck_id,
      name: "index_limitless_mappings_on_base_deck",
      unique: true, where: "limitless_variant IS NULL"
  end
end
