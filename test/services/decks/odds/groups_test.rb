require "test_helper"

# Deck -> the groups every probability on the page is computed over. Three rules, and the suite goes
# red on each of them independently.
class Decks::Odds::GroupsTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  # The app's existing "same card, any printing" key. 2 Budew (PRE) plus 2 Budew (ASC) is one group
  # of 4 copies, which is what both the rules and the probabilities say — grouping by printing
  # instead splits it into two 2-ofs and understates every number about it.
  test "printings of one card merge into one group" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 2)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

    result = Decks::Odds::Groups.call(@deck)

    assert_equal 1, result.entries.size
    entry = result.entries.first
    assert_equal "budew_shared", entry.key
    assert_equal 4, entry.copies
    assert_equal "Budew", entry.name
    assert_equal 4, result.deck_size
    # Both printings carry the same `name`, so nothing above can tell which one the group is
    # labelled from. ASC 16 is the lowest set code of the two and therefore the one that names it.
    assert_equal cards(:budew_asc), entry.card
  end

  # The other half of that choice: the set numbers are compared as strings, so "112" precedes "9".
  # Both printings sit in one set, which is the only shape where the comparison's second element
  # decides anything at all — and the shape a numeric comparison would silently pass.
  test "the printing naming a group is chosen by string order, not by number" do
    ledger_9 = odds_ledger("9")
    ledger_112 = odds_ledger("112")
    assert_equal ledger_9.fingerprint, ledger_112.fingerprint, "the two printings must be one group"

    @deck.deck_cards.create!(card: ledger_9, quantity: 1)
    @deck.deck_cards.create!(card: ledger_112, quantity: 1)

    result = Decks::Odds::Groups.call(@deck)

    assert_equal 1, result.entries.size
    assert_equal ledger_112, result.entries.first.card,
      %(set numbers are compared as strings: "112" sorts before "9")
  end

  # The measurement behind this: 2 196 Pokémon in the development catalogue carry stage = "Basic",
  # and so do 50 Basic Energy cards. Testing `stage` alone counts a deck's Energy toward the
  # mulligan — which makes the mulligan rate wrong in the reassuring direction, by a lot, on exactly
  # the decks that play the most Energy.
  #
  # update_column and not update!: `stage` is not part of Card#compute_fingerprint for an Energy, but
  # a save would recompute the fingerprint from the name and move this row out of the fixture key the
  # rest of the suite reads.
  test "a Basic Energy is not a Basic Pokemon" do
    energy = cards(:basic_psychic_energy)
    energy.update_column(:stage, "Basic")

    @deck.deck_cards.create!(card: energy, quantity: 8)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)

    result = Decks::Odds::Groups.call(@deck)

    assert_equal 12, result.deck_size
    assert_equal 4, result.basics, "the eight Energy must not count toward the mulligan"
  end

  # A card with no fingerprint can only come from a write that bypassed callbacks, and there are two
  # such printings in the fixtures. They must form a group each rather than merging into one group
  # of everything unfingerprinted — which a bare `group_by(&:fingerprint)` would do, since nil is a
  # perfectly good Hash key.
  test "cards without a fingerprint do not merge with each other" do
    @deck.deck_cards.create!(card: cards(:special_prism_energy_asc), quantity: 2)
    @deck.deck_cards.create!(card: cards(:special_prism_energy_blk), quantity: 2)

    result = Decks::Odds::Groups.call(@deck)

    assert_equal 2, result.entries.size
    assert_equal [ 2, 2 ], result.entries.map(&:copies)
    assert_equal result.entries.map(&:key).uniq.size, result.entries.size
  end

  # A Stage 1 Pokémon is a Pokémon and not a Basic — the other half of the stage rule.
  test "an evolution is not a Basic" do
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 3)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)

    result = Decks::Odds::Groups.call(@deck)

    assert_equal 7, result.deck_size
    assert_equal 4, result.basics
  end

  # Roles ride on the fingerprint, the same key the groups use, so a label recorded from one
  # printing reaches every printing of that card. `rejected` rows are a human saying no and are not
  # a role the deck plays.
  #
  # `switch` (40) and `recovery` (50) and not `draw` (10) and `gust` (30): the two roles have to
  # disagree about their order, or a slug sort — and no sort at all, since the rows are written
  # recovery-first — passes while claiming to assert position order. Both positions are CardLabel's.
  test "role labels attach to a group through its fingerprint" do
    recovery = CardLabel.create!(slug: "recovery", name: "Recovery", family: "role", position: 50)
    switch = CardLabel.create!(slug: "switch", name: "Switch", family: "role", position: 40)
    ace = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)

    CardLabelAssignment.create!(card_label: recovery, fingerprint: "budew_shared",
                                card: cards(:budew_pre), source: "curated")
    CardLabelAssignment.create!(card_label: switch, fingerprint: "budew_shared",
                                card: cards(:budew_pre), source: "curated")
    CardLabelAssignment.create!(card_label: ace, fingerprint: "budew_shared",
                                card: cards(:budew_pre), source: "curated")
    CardLabelAssignment.create!(card_label: switch, fingerprint: "honedge_fp",
                                card: cards(:honedge), source: "curated", rejected: true)

    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 3)

    result = Decks::Odds::Groups.call(@deck)
    by_key = result.entries_by_key

    assert_equal %w[switch recovery], by_key["budew_shared"].roles.map(&:slug),
      "roles come back in position order, and the type family is not a role"
    assert_empty by_key["honedge_fp"].roles, "a rejected assignment is a refusal, not a role"
    assert_equal [ switch, recovery ], result.roles
    assert_equal 3, result.uncurated_copies
  end

  # One query for the whole deck's labels, not one per group — and one pair of queries for the
  # rows, not one per card. Both measurements are taken on a deck loaded fresh from the database,
  # because a deck whose `deck_cards` were built by `create!` carries its `card` association already
  # loaded: measuring that against a cold one compares two different questions, and measuring two
  # warm ones hides the per-card N+1 this test exists to catch.
  #
  # `uncached` because the label read is one identical statement per group: the query cache answers
  # every repeat of it and SQLCounter skips a CACHE event, so a service asking once per group
  # measures the same as one asking once per deck. Measured — that sabotage stayed green until this
  # block was here.
  test "the labels cost one query however many groups there are" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2)
    small = count_queries { ActiveRecord::Base.uncached { Decks::Odds::Groups.call(Deck.find(@deck.id)) } }

    [ :trainer_card, :froakie_cri, :budew_asc, :basic_psychic_energy ].each do |name|
      @deck.deck_cards.create!(card: cards(name), quantity: 2)
    end
    large = count_queries { ActiveRecord::Base.uncached { Decks::Odds::Groups.call(Deck.find(@deck.id)) } }

    assert_equal small, large, "query count grew with the decklist: #{small} -> #{large}"
  end

  private

  # Two printings of one Trainer inside one invented set. The fingerprint of a non-Pokémon is the
  # hash of its name alone, so naming them identically is what puts them in one group.
  def odds_ledger(number)
    Card.create!(name: "Odds Ledger", card_type: "Trainer", set_name: "ZZY", set_number: number,
                 rarity: "Common")
  end
end
