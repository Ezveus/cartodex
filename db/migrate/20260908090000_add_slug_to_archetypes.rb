class AddSlugToArchetypes < ActiveRecord::Migration[8.1]
  def up
    add_column :archetypes, :slug, :string

    backfill_slugs

    change_column_null :archetypes, :slug, false
    add_index :archetypes, :slug, unique: true
    # NOT NULL is not enough, and neither is the index: `""` offends neither, and only a *second*
    # blank collides. This is the guarantee behind Archetype's readable refusal — the same
    # division of labour the fingerprint pair and (set_name, set_number) already have, except
    # that a blank cannot be expressed as an index. It matters because `assign_slug` is a
    # before_save, so a validation-skipping write reaches the column with the validation's
    # refusal skipped.
    add_check_constraint :archetypes, "slug <> ''", name: "archetypes_slug_not_blank"
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
    # Every row, not `where(slug: nil)` as AddKeyToDecks scopes its own backfill: a key is
    # random and must never be regenerated, while a slug is derived and re-deriving it is a
    # no-op — and rewriting unconditionally is what lets ArchetypeTest seed a wrong value and
    # watch this correct it.
    #
    # `update_all`, for the reason AddKeyToDecks spells out: this fills a column, it does not
    # re-validate history. Going through the model would re-run `sync_fingerprints` and the
    # fingerprint-pair uniqueness check on rows written long before either, and a single
    # pre-existing offender would abort the migration halfway, leaving a nullable column and no
    # index.
    Archetype.reset_column_information
    Archetype.pluck(:id, :name).each do |id, name|
      Archetype.where(id: id).update_all(slug: self.class.slug_for(name))
    end

    reject_blank_slugs!
  end

  # Inside the backfill rather than beside it in `up`, and that is not tidiness: filling the
  # column and refusing what cannot be filled are one operation, so `up` makes one call instead
  # of two and both halves are reached by the two tests that exercise this method. (What no test
  # here can see is `up` failing to call `backfill_slugs` at all — CI loads db/schema.rb and never
  # runs a migration. AddFingerprintsToArchetypes' three checks have exactly the same gap.)
  #
  # The check is **not** redundant beside the two constraints `up` adds afterwards, which is what
  # an earlier version of this file claimed. Measured: with one row at `""`,
  # `change_column_null` passes (only NULL offends it) and so does the UNIQUE index (only a
  # *second* blank collides), so a single blank slug shipped — and the consequence is worse than
  # "unaddressable": `archetype_path` on that row emits `/archetypes/`, the collection path, so
  # the catalog links the row to the listing it sits in, and the model's own blank refusal then
  # makes the row unsavable from the admin panel, so it cannot be repaired either. 79 rows in
  # production produced 79 distinct, non-blank slugs, so this is not expected — "not expected" is
  # what a check is for.
  #
  # Names the offenders rather than the count, the way AddFingerprintsToArchetypes' checks do:
  # whoever hits this has to go and rename a row, and "3 archetypes have no slug" does not say
  # which.
  def reject_blank_slugs!
    blank = Archetype.where(slug: "").pluck(:id, :name)
    return if blank.empty?

    raise "#{blank.size} archetype(s) have a name no URL can carry, so no slug could be " \
          "derived — rename them and re-run: " +
          blank.map { |id, name| "##{id} #{name.inspect}" }.join(", ")
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
