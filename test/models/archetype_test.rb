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

  # The `search` scope spells its second join alias by hand, and Rails derives
  # that alias from the association name — so renaming the association breaks
  # the scope at query time, not at load time. These two run the SQL.
  test "search runs against the renamed associations" do
    assert_respond_to archetypes(:ogerpon), :primary_card
    assert_respond_to archetypes(:ogerpon), :secondary_card
    assert_nothing_raised { Archetype.search("Ogerpon").to_a }
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
  # die on NOT NULL instead of reaching the index this test is about.
  test "the database refuses two single-member archetypes on the same fingerprint" do
    duplicate = Archetype.new(primary_card: cards(:teal_mask_ogerpon_ex), name: "Ogerpon again",
      primary_fingerprint: "ogerpon_shared", secondary_fingerprint: "")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  # Identity is the fingerprint pair, so a different printing of the same card is
  # the same archetype — this is what makes the printing a display reference.
  test "the database refuses a second archetype built from another printing of the same card" do
    reprint = cards(:froakie_cri)
    reprint.update_column(:fingerprint, "ogerpon_shared")
    duplicate = Archetype.new(primary_card: reprint, name: "Ogerpon reprint",
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
      { name: "Clone A", name_normalized: "clone a", primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current },
      { name: "Clone B", name_normalized: "clone b", primary_card_id: cards(:doublade).id,
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
      { name: "Clone A", name_normalized: "clone a", primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current },
      { name: "Clone B", name_normalized: "clone b", primary_card_id: cards(:doublade).id,
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
        primary_card_id: cards(:trainer_card).id, secondary_card_id: nil,
        primary_fingerprint: "", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current },
      { name: "No Secondary Fingerprint", name_normalized: "no secondary fingerprint",
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

  private

  def migration_filename(suffix)
    Dir.children(Rails.root.join("db/migrate")).find { |f| f.end_with?("_#{suffix}.rb") } ||
      raise("no migration ending in _#{suffix}.rb")
  end
end
