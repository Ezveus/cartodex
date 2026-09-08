class AddSlugToArchetypes < ActiveRecord::Migration[8.1]
  def up
    add_column :archetypes, :slug, :string

    backfill_slugs

    # A collision or a blank the pre-migration measurement did not see fails here rather than
    # shipping a row no URL can address. 79 rows in production produced 79 distinct, non-blank
    # slugs, so neither is expected — but "not expected" is what an index is for.
    change_column_null :archetypes, :slug, false
    add_index :archetypes, :slug, unique: true
  end

  def down
    remove_index :archetypes, :slug
    remove_column :archetypes, :slug
  end

  # Public, and called by name, for the reason AddFingerprintsToArchetypes' three checks are:
  # CI loads db/schema.rb and never runs a migration, so a backfill written inline is code the
  # suite cannot reach — and this one carries a *rule* that must agree with Archetype#assign_slug
  # or production gets slugs that are wrong while being unique and non-blank, which no index
  # catches. ArchetypeTest requires this file and asserts both halves.
  def backfill_slugs
    # `update_all`, for the reason AddKeyToDecks spells out: this fills a column, it does not
    # re-validate history. Going through the model would re-run `sync_fingerprints` and the
    # fingerprint-pair uniqueness check on rows written long before either, and a single
    # pre-existing offender would abort the migration halfway, leaving a nullable column and no
    # index.
    Archetype.reset_column_information
    Archetype.pluck(:id, :name).each do |id, name|
      Archetype.where(id: id).update_all(slug: self.class.slug_for(name))
    end
  end

  # Spelled out here rather than read off the model, so this keeps working after Archetype has
  # moved on: `name_normalized` is `name.squish.downcase` and the slug is that, parameterized.
  # Derived from `name` and not from the mirror because the mirror is nullable and a row written
  # by a callback-bypassing insert can carry nil in it.
  #
  # The `squish.downcase` is measured **redundant** beside `parameterize`, which folds case and
  # runs of separators itself — checked on seven awkward names, including a double-spaced one, a
  # mixed-case one and `Nidoran♀`. It is kept because it makes this the visibly *same* rule the
  # model reads through `name_normalized`, rather than a second rule that happens to agree; a
  # reader tempted to trim it should know that a `tr(" ", "-")`-shaped simplification is what
  # ArchetypeTest's agreement assertion actually catches.
  def self.slug_for(name)
    name.to_s.squish.downcase.parameterize
  end
end
