# One store for what a card is beyond its card_type, and — from stage 2 — for what it does.
#
# The vocabulary is a table rather than a constant because half of it moves: Ancient and Future
# arrived mid-block in Scarlet & Violet, ACE SPEC was revived from Black & White in the middle of
# the same block, and Limitless's own `is:` documentation is already incomplete (is:ancient,
# is:future and is:tera all answer and none is listed). A closed list in code is a deploy per set.
class CreateCardLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :card_labels do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :family, null: false
      t.integer :position, null: false, default: 0
      t.text :description
      # The Limitless search token a `type` label is imported by ("is:ace"). Nullable: a `role`
      # label has none, and a curated `type` label need not have one either.
      t.string :source_query
      t.timestamps
    end
    add_index :card_labels, :slug, unique: true
    add_index :card_labels, [ :family, :position ]

    create_table :card_label_assignments do |t|
      # index: false — the composite UNIQUE below leads with this column and serves every lookup
      # a plain index would.
      t.references :card_label, null: false, foreign_key: true, index: false
      # The identity: "same card, any printing", the key Archetypes::CardStats already groups on.
      t.string :fingerprint, null: false
      # The printing the decision was made from — Archetype's primary_card_id / primary_fingerprint
      # pair, for the same reason: it is what makes a fingerprint drift repairable out of band
      # rather than silent.
      t.references :card, foreign_key: true
      t.string :source, null: false
      # A human saying no. Deleting the row instead would have the next suggestion run propose it
      # again, forever.
      t.boolean :rejected, null: false, default: false
      t.timestamps
    end
    add_index :card_label_assignments, [ :card_label_id, :fingerprint ], unique: true
    add_index :card_label_assignments, :fingerprint
  end
end
