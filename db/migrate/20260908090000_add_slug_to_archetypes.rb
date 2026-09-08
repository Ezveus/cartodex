class AddSlugToArchetypes < ActiveRecord::Migration[8.1]
  def up
    add_column :archetypes, :slug, :string

    # `update_all`, for the reason AddKeyToDecks spells out: this fills a column, it does not
    # re-validate history. Going through the model would re-run `sync_fingerprints` and the
    # fingerprint-pair uniqueness check on rows written long before either, and a single
    # pre-existing offender would abort the migration halfway, leaving a nullable column and no
    # index.
    #
    # The rule is spelled out here rather than read from the model, so this keeps working after
    # Archetype has moved on: `name_normalized` is `name.squish.downcase` and the slug is that,
    # parameterized. Derived from `name` rather than from `name_normalized` because the mirror
    # is nullable and a row written by a callback-bypassing insert can carry nil in it.
    Archetype.reset_column_information
    Archetype.pluck(:id, :name).each do |id, name|
      Archetype.where(id: id).update_all(slug: name.to_s.squish.downcase.parameterize)
    end

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
end
