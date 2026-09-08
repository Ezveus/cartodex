require "test_helper"

class ArchetypeTest < ActiveSupport::TestCase
  test "search matches on the archetype name" do
    assert_includes Archetype.search("Ogerpon"), archetypes(:ogerpon)
  end

  test "search matches on a member Pokémon's name" do
    assert_includes Archetype.search("Budew"), archetypes(:budew_ogerpon)
  end

  test "search treats LIKE metacharacters as literals" do
    assert_empty Archetype.search("b_dew"), "_ must not act as a wildcard"
    assert_empty Archetype.search("bud%w"), "% must not act as a wildcard"
  end

  # The stored name carries an uppercase accented letter on purpose: SQLite's LIKE folds F/f but
  # not É/é, so a lowercase query can only match through name_normalized. Were this scope to read
  # the plain `name` columns again, these two tests would go red — that's what they exist for.
  test "search ignores case on accented letters in the archetype name" do
    archetype = archetypes(:ogerpon)
    archetype.update!(name: "FLABÉBÉ Box", custom_name: "1")

    %w[FLABÉBÉ Flabébé flabébé].each do |query|
      assert_includes Archetype.search(query), archetype, "#{query.inspect} must match"
    end
  end

  # Drift protection for the third column of the scope: name_normalized is read off
  # secondary_cards_archetypes (the join alias), not primary_cards_archetypes or
  # archetypes itself. Both the archetype's own name and the primary Pokémon's name are renamed
  # away from the query so a match can only come through the secondary Pokémon's column. The
  # secondary is swapped to a card no other archetype fixture references (teal_mask_ogerpon_ex is
  # also archetypes(:ogerpon)'s primary — renaming it would make that fixture match too).
  test "search matches on the secondary Pokémon's name" do
    archetype = archetypes(:budew_ogerpon)
    secondary = cards(:froakie_cri)
    archetype.update!(secondary_card: secondary, name: "Mystery Box", custom_name: "1")
    secondary.update!(name: "Flittle")

    assert_includes Archetype.search("Flittle"), archetype

    archetype.update!(secondary_card: nil, custom_name: "1")
    assert_empty Archetype.search("Flittle"),
      "must not match without the secondary Pokémon: the archetype's own name and the primary's are both unrelated to the query"
  end

  test "search ignores case on accented letters in a member Pokémon's name" do
    cards(:budew_pre).update!(name: "FLABÉBÉ")

    %w[FLABÉBÉ Flabébé flabébé].each do |query|
      assert_includes Archetype.search(query), archetypes(:budew_ogerpon), "#{query.inspect} must match"
    end
  end

  test "every archetype fixture carries the normalization its name implies" do
    Archetype.find_each do |archetype|
      assert_equal archetype.name.downcase, archetype.name_normalized,
        "#{archetype.name.inspect} fixture is out of step"
    end
  end

  # The other half of what the fixture file's comment promises. Fixtures skip
  # callbacks, so the pair is spelled out by hand and nothing keeps it in step
  # with cards.yml — edit a card's fingerprint and the archetype fixtures would
  # silently describe a state sync_fingerprints can never produce, while the
  # detector tests (which read the live card) keep passing.
  test "every archetype fixture carries the fingerprint pair its member cards imply" do
    Archetype.includes(:primary_card, :secondary_card).find_each do |archetype|
      assert_equal archetype.primary_card.fingerprint, archetype.primary_fingerprint,
        "#{archetype.name.inspect} fixture is out of step with its primary card"
      assert_equal archetype.secondary_card&.fingerprint.to_s, archetype.secondary_fingerprint,
        "#{archetype.name.inspect} fixture is out of step with its secondary card"
    end
  end

  # The `search` scope spells its second join alias by hand, and Rails derives
  # that alias from the association name — so renaming the association breaks
  # the scope at query time, not at load time. These two run the SQL.
  test "search runs against the renamed associations" do
    assert_respond_to archetypes(:ogerpon), :primary_card
    assert_respond_to archetypes(:ogerpon), :secondary_card
    assert_nothing_raised { Archetype.search("Ogerpon").to_a }
  end

  # A standing is another member's public record of a real placement; deleting the archetype
  # *tag* it carries must not silently take that record with it. archetype_id is NOT NULL on a
  # standing, so :nullify (this model's cascade for deck_results/decks) is not available here —
  # unlike those two, this is restrict_with_error.
  test "refuses to be destroyed while a standing names it" do
    archetype = archetypes(:standings_marker)
    assert_predicate archetype.tournament_standings, :any?, "sanity: fixture standings reference it"

    assert_no_difference -> { Archetype.count } do
      assert_no_difference -> { TournamentStanding.count } do
        assert_not archetype.destroy
      end
    end

    assert_not_empty archetype.errors
  end

  # --- Fingerprint identity ---

  test "the fingerprint pair is filled from the member cards on save" do
    archetype = Archetype.create!(primary_card: cards(:doublade), secondary_card: cards(:bosss_orders_meg))

    assert_equal "doublade_fp", archetype.primary_fingerprint
    assert_equal "bosss_orders_meg_fp", archetype.secondary_fingerprint
  end

  # The empty string, never NULL: SQLite treats NULLs as distinct, so a nullable
  # column would let two single-member archetypes through the unique index —
  # exactly the hole the card-id index left open.
  test "a missing secondary is stored as the empty string" do
    archetype = Archetype.create!(primary_card: cards(:doublade))

    assert_equal "", archetype.secondary_fingerprint
  end

  # The pair is spelled out rather than left to sync_fingerprints: `validate: false`
  # skips before_validation too, so the callback would not run and the row would
  # die on NOT NULL instead of reaching the index this test is about. `slug` is spelled out for
  # exactly that reason and must not collide with a fixture's, or the row dies on the *slug*
  # index and this test would pass while asserting nothing about the fingerprint pair.
  test "the database refuses two single-member archetypes on the same fingerprint" do
    duplicate = Archetype.new(primary_card: cards(:teal_mask_ogerpon_ex), name: "Ogerpon again",
      slug: "ogerpon-again",
      primary_fingerprint: "ogerpon_shared", secondary_fingerprint: "")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  # Identity is the fingerprint pair, so a different printing of the same card is
  # the same archetype — this is what makes the printing a display reference.
  test "the database refuses a second archetype built from another printing of the same card" do
    reprint = cards(:froakie_cri)
    reprint.update_column(:fingerprint, "ogerpon_shared")
    duplicate = Archetype.new(primary_card: reprint, name: "Ogerpon reprint",
      slug: "ogerpon-reprint",
      primary_fingerprint: "ogerpon_shared", secondary_fingerprint: "")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "a card with no fingerprint cannot be designated" do
    archetype = Archetype.new(primary_card: cards(:trainer_card), name: "Boss")

    assert_not archetype.valid?
    assert_includes archetype.errors[:primary_fingerprint], "can't be blank"
  end

  # "" means "no secondary": a present-but-unscraped secondary must not be
  # silently treated as missing, or it could collide with an unrelated
  # single-member archetype on the same primary.
  test "an unfingerprinted secondary cannot be designated either" do
    archetype = Archetype.new(primary_card: cards(:doublade), secondary_card: cards(:trainer_card),
      name: "Doublade / Boss")

    assert_not archetype.valid?
    assert_includes archetype.errors[:secondary_fingerprint], "can't be blank"
  end

  # The migration refuses to add the index when a duplicate pair exists, and names
  # the offenders rather than deleting one — decks and deck_results point at these
  # rows. Once the index is in place a duplicate cannot be created, so the only way
  # to exercise the query is to drop the index for the length of this test. The
  # suite's transactional fixtures roll the DDL back.
  test "the migration's duplicate detection names the offenders" do
    require Rails.root.join("db/migrate/#{migration_filename('add_fingerprints_to_archetypes')}")

    connection = ActiveRecord::Base.connection
    connection.remove_index :archetypes, name: "index_archetypes_on_fingerprint_pair"
    Archetype.insert_all([
      { name: "Clone A", name_normalized: "clone a", slug: "clone-a",
        primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current },
      { name: "Clone B", name_normalized: "clone b", slug: "clone-b",
        primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current }
    ])

    duplicates = AddFingerprintsToArchetypes.new.duplicate_pairs

    # GROUP_CONCAT's element order is not guaranteed by SQLite, so assert on
    # membership rather than on a joined string.
    assert_equal 1, duplicates.size
    assert_includes duplicates.first["names"], "Clone A"
    assert_includes duplicates.first["names"], "Clone B"
  end

  # The migration's refusal (raise, not a deleted row) is a global constraint —
  # this exercises the actual raise, not just the query behind it.
  test "the migration's reject_duplicates! actually raises and names the offenders" do
    require Rails.root.join("db/migrate/#{migration_filename('add_fingerprints_to_archetypes')}")

    connection = ActiveRecord::Base.connection
    connection.remove_index :archetypes, name: "index_archetypes_on_fingerprint_pair"
    Archetype.insert_all([
      { name: "Clone A", name_normalized: "clone a", slug: "clone-a",
        primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current },
      { name: "Clone B", name_normalized: "clone b", slug: "clone-b",
        primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current }
    ])

    error = assert_raises(RuntimeError) { AddFingerprintsToArchetypes.new.send(:reject_duplicates!) }

    assert_match "Clone A", error.message
    assert_match "Clone B", error.message
  end

  # Covers both halves: a blank primary_fingerprint, and a present secondary_card_id
  # whose secondary_fingerprint is blank (an unscraped secondary, not a missing one).
  test "the migration's reject_unfingerprinted! actually raises and names which half is missing" do
    require Rails.root.join("db/migrate/#{migration_filename('add_fingerprints_to_archetypes')}")

    Archetype.insert_all([
      { name: "No Primary Fingerprint", name_normalized: "no primary fingerprint",
        slug: "no-primary-fingerprint",
        primary_card_id: cards(:trainer_card).id, secondary_card_id: nil,
        primary_fingerprint: "", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current },
      { name: "No Secondary Fingerprint", name_normalized: "no secondary fingerprint",
        slug: "no-secondary-fingerprint",
        primary_card_id: cards(:doublade).id, secondary_card_id: cards(:trainer_card).id,
        primary_fingerprint: "doublade_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current }
    ])

    error = assert_raises(RuntimeError) { AddFingerprintsToArchetypes.new.send(:reject_unfingerprinted!) }

    assert_match "No Primary Fingerprint", error.message
    assert_match "(primary)", error.message
    assert_match "No Secondary Fingerprint", error.message
    assert_match "(secondary)", error.message
  end

  # --- The slug, which is the archetype's address ---
  #
  # Derived from name_normalized on every save and kept nowhere else: renaming an archetype
  # moves its URL and breaks links to the old one, which is the decision recorded in
  # docs/superpowers/specs/2026-09-08-public-archetypes-and-slugs-design.md.

  test "the slug is the parameterized name" do
    archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: "1",
                                  name: "Mega Absol ex / N's Zoroark ex")

    assert_equal "mega-absol-ex-n-s-zoroark-ex", archetype.slug
    assert_equal archetype.name_normalized.parameterize, archetype.slug
  end

  # The callback is a before_validation and not a before_create, and nothing else in the app
  # would report the difference: no page reads a stale slug, so a renamed archetype would keep
  # answering on its old URL and every link the page emits would keep working.
  test "renaming an archetype moves its slug" do
    archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: "1",
                                  name: "Metal Toolbox")
    assert_equal "metal-toolbox", archetype.slug

    archetype.update!(name: "Steel Box", custom_name: "1")

    assert_equal "steel-box", archetype.slug
    assert_equal "steel-box", archetype.reload.slug
  end

  # assign_slug is declared after auto_generate_name, and this is the test that says so: an
  # archetype created the way Api::ArchetypesController creates one carries no name at all until
  # that callback has run, so a slug computed first would be blank — and blank is refused, which
  # would turn every API create into a 422.
  test "an archetype named by its member cards gets the slug of the generated name" do
    archetype = Archetype.create!(primary_card: cards(:doublade),
                                  secondary_card: cards(:bosss_orders_meg))

    assert_equal "Doublade / Boss's Orders", archetype.name
    assert_equal "doublade-boss-s-orders", archetype.slug
  end

  test "changing the member cards of an auto-named archetype moves its slug" do
    archetype = Archetype.create!(primary_card: cards(:doublade),
                                  secondary_card: cards(:bosss_orders_meg))

    archetype.update!(secondary_card: nil)

    assert_equal "Doublade", archetype.name
    assert_equal "doublade", archetype.reload.slug
  end

  # The hazard, pinned rather than fixed. `custom_name` is a non-persisted `attr_accessor`, so
  # `auto_generate_name` fires on any save that does not set it — and now that the name decides
  # the *address*, a bare save rewrites a public URL. Not live: the only savers are
  # `Admin::ArchetypesController` (which sets `custom_name` whenever the submitted name is
  # present, and whose blank-name path is deliberate) and `Api::ArchetypesController#create`
  # (new records only); `Archetypes::FingerprintSync` writes with `update_columns` and
  # `dependent: :nullify` with `update_all`. The day anything calls `save`/`update!` on an
  # archetype for an unrelated reason — a parent reassignment, a bulk action — every hand-named
  # archetype loses its name *and* every link ever shared to it. Fixing that means persisting
  # `custom_name`, which is a schema decision about how archetypes are named and not about
  # publishing pages, so this test states the behaviour instead of asserting the one we want.
  test "a bare save regenerates a hand-typed name, and therefore the address" do
    archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: "1",
                                  name: "Metal Toolbox")
    assert_equal "metal-toolbox", archetype.slug

    # Reloaded first, which is the realistic shape: the accessor lives on the instance that was
    # handed the typed name, so it is a *fresh* read of the row that has lost it. Any code path
    # that finds an archetype and saves it is this.
    reloaded = Archetype.find(archetype.id)
    reloaded.save!

    assert_equal "Doublade", reloaded.name, "the accessor is not persisted, so the name regenerates"
    assert_equal "doublade", reloaded.reload.slug, "and the public address moves with it"
  end

  test "to_param is the slug, so every URL of this archetype names it" do
    archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: "1",
                                  name: "Metal Toolbox")

    assert_equal "metal-toolbox", archetype.to_param
  end

  # Two archetypes may share nothing but punctuation, and the slug is what makes that a
  # collision. It is refused rather than disambiguated, and the error lands on :name because
  # that is the field the admin form has — "Slug has already been taken" names nothing a user
  # typed. The escape hatch is the custom name they are already typing.
  test "a name whose slug collides with another archetype's is refused, on :name" do
    Archetype.create!(primary_card: cards(:doublade), custom_name: "1",
                      name: "Gardevoir ex / Munkidori")

    duplicate = Archetype.new(primary_card: cards(:doublade),
                              secondary_card: cards(:bosss_orders_meg),
                              custom_name: "1", name: "Gardevoir ex Munkidori")

    assert_not duplicate.valid?
    assert_empty duplicate.errors[:slug], "the error belongs on the field the form has"
    assert_match(/Gardevoir ex \/ Munkidori/, duplicate.errors[:name].join)
  end

  # An archetype may not carry a name no URL can express. Zero rows and zero card names in the
  # catalogue are in that state; #111 (Japanese card sets) is what reaches it, and this is where
  # the refusal is written down so that issue has something to argue with.
  test "a name with nothing a URL can carry is refused, on :name" do
    archetype = Archetype.new(primary_card: cards(:doublade), custom_name: "1", name: "ポケモン")

    assert_not archetype.valid?
    assert_empty archetype.errors[:slug]
    assert_not_empty archetype.errors[:name]
  end

  # The other half of the same division of labour, and a hole the first version of this feature
  # opened by accident: `assign_slug` is a before_save, so a validation-skipping save still runs
  # it — and it happily wrote `""`, which `NOT NULL` does not refuse and which the UNIQUE index
  # refuses only on a *second* offender. `archetype_path` on such a row emits `/archetypes/`, the
  # collection path, so the row links to the listing it sits in and cannot be repaired from the
  # panel (the model's own blank refusal rejects any save of it). A CHECK constraint is what makes
  # the state unreachable rather than merely invalid.
  test "the database refuses a blank slug even when validations are skipped" do
    archetype = Archetype.new(primary_card: cards(:doublade), custom_name: "1", name: "ポケモン",
                              primary_fingerprint: cards(:doublade).fingerprint,
                              secondary_fingerprint: "")

    assert_raises(ActiveRecord::StatementInvalid) { archetype.save!(validate: false) }
  end

  # `resources :archetypes` in the admin namespace emits GET /admin/archetypes/new *before*
  # GET /admin/archetypes/:id, so an archetype whose slug is "new" has no reachable admin show
  # page — and `#create`/`#update` both redirect to `admin_archetype_path`, which would land the
  # admin on a blank "New Archetype" form carrying the flash "Archetype updated.": a 200 that
  # reads as if the edit had been lost. Reachable by typing "New" in the one field the form has.
  test "a name whose slug would shadow a route is refused, on :name" do
    [ "New", "new", "NEW" ].each do |name|
      archetype = Archetype.new(primary_card: cards(:doublade), custom_name: "1", name: name)

      assert_not archetype.valid?, "#{name.inspect} must be refused"
      assert_empty archetype.errors[:slug]
      assert_match(/reserved/, archetype.errors[:name].join)
    end
  end

  # The validation is for the readable error; the index is the guarantee. Same division of
  # labour as (set_name, set_number) on Card and the fingerprint pair above.
  test "the unique index refuses a duplicate slug the validation never saw" do
    archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: "1",
                                  name: "Metal Toolbox")
    other = Archetype.create!(primary_card: cards(:doublade),
                              secondary_card: cards(:bosss_orders_meg),
                              custom_name: "1", name: "Steel Toolbox")

    assert_raises(ActiveRecord::RecordNotUnique) do
      other.update_column(:slug, archetype.slug)
    end
  end

  # The third half of what the fixture file's comment promises: fixtures skip callbacks, so the
  # slug is spelled out by hand beside name_normalized and nothing keeps the two in step.
  #
  # Derived from `name` and not from `name_normalized` on purpose, even though the callback reads
  # the mirror: the sibling assertion above compares `name.downcase` to `name_normalized`
  # *without* squishing, so a fixture whose name carries a double space could satisfy both checks
  # while disagreeing with what a save would produce. Going back to `name` closes that.
  test "every archetype fixture carries the slug its name implies" do
    Archetype.find_each do |archetype|
      assert_equal archetype.name.squish.downcase.parameterize, archetype.slug,
        "#{archetype.name.inspect} fixture is out of step"
    end
  end

  # CI loads db/schema.rb and never runs a migration, so the backfill is code the suite would
  # otherwise never execute — and it carries its own copy of the slug rule, spelled out so the
  # migration survives the model moving on. A divergence between the two produces slugs that are
  # wrong while being unique and non-blank, which is exactly what neither the NOT NULL nor the
  # UNIQUE index can catch. Same reason AddFingerprintsToArchetypes' three checks are called by
  # name from this file.
  test "the migration's backfill writes what the model's callback would" do
    require Rails.root.join("db/migrate/#{migration_filename('add_slug_to_archetypes')}")

    [ "Mega Absol ex / N's Zoroark ex", "  Double  Spaced  Name  ", "Flabébé Box",
      "Nidoran♀ Toolbox" ].each do |name|
      archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: "1", name: name)

      assert_equal archetype.slug, AddSlugToArchetypes.slug_for(name),
        "the migration and the callback disagree on #{name.inspect}"

      archetype.destroy!
    end
  end

  # The readable half of the blank refusal. `change_column_null` only refuses NULL and the UNIQUE
  # index only refuses a *second* blank, so what actually stops a blank shipping is the CHECK
  # constraint — and that constraint is added **after** the backfill, so during a real migration
  # run the blank is written first and this is what names it. Without it `add_check_constraint`
  # would fail on a row it cannot identify.
  #
  # The constraint is dropped for the length of the test, exactly as the fingerprint tests below
  # drop the unique index they are about: it is what makes the state unreachable, so a test about
  # the window before it exists has to reopen that window. Transactional fixtures roll the DDL
  # back.
  test "the migration names a blank slug the CHECK constraint would refuse unhelpfully" do
    require Rails.root.join("db/migrate/#{migration_filename('add_slug_to_archetypes')}")

    ActiveRecord::Base.connection.remove_check_constraint :archetypes, name: "archetypes_slug_not_blank"
    Archetype.insert_all([
      { name: "ポケモン", name_normalized: "ポケモン", slug: "",
        primary_card_id: cards(:doublade).id,
        primary_fingerprint: "blank_slug_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current }
    ])

    # Through backfill_slugs, not the check directly: the two are one operation, so this also
    # asserts that filling the column cannot silently skip the refusal.
    error = assert_raises(RuntimeError) { AddSlugToArchetypes.new.backfill_slugs }

    assert_match "ポケモン", error.message
    assert_match "no URL can carry", error.message
  end

  test "the migration's backfill actually writes the column" do
    require Rails.root.join("db/migrate/#{migration_filename('add_slug_to_archetypes')}")

    # A placeholder slug rather than none: the column is NOT NULL, and what this exercises is the
    # loop overwriting a wrong value, not the nullable window the migration opens for itself.
    Archetype.insert_all([
      { name: "Backfill  Me", name_normalized: "backfill me", slug: "placeholder",
        primary_card_id: cards(:doublade).id,
        primary_fingerprint: "backfill_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current }
    ])

    AddSlugToArchetypes.new.backfill_slugs

    assert_equal "backfill-me", Archetype.find_by!(name: "Backfill  Me").slug
    # Every other row is rewritten too, and must come out where it went in.
    assert_equal "teal-mask-ogerpon-ex", archetypes(:ogerpon).reload.slug
  end

  private

  def migration_filename(suffix)
    Dir.children(Rails.root.join("db/migrate")).find { |f| f.end_with?("_#{suffix}.rb") } ||
      raise("no migration ending in _#{suffix}.rb")
  end
end
