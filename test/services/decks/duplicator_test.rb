require "test_helper"

class Decks::DuplicatorTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.update!(name: "Original", description: "A fine deck")
    @deck.deck_cards.destroy_all
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 3)
  end

  test "creates a new deck owned by the same user" do
    new_deck = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_not_equal @deck.id, new_deck.id
    assert_equal @deck.user, new_deck.user
  end

  test "prefixes the name with 'Copy of '" do
    new_deck = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_equal "Copy of Original", new_deck.name
  end

  test "copies the description" do
    new_deck = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_equal "A fine deck", new_deck.description
  end

  test "copies deck_cards with their quantities" do
    new_deck = Decks::Duplicator.call(@deck, user: @deck.user)

    pairs = new_deck.deck_cards.map { |dc| [ dc.card_id, dc.quantity ] }.sort
    expected = @deck.deck_cards.map { |dc| [ dc.card_id, dc.quantity ] }.sort

    assert_equal expected, pairs
  end

  test "duplicates a deck with no cards" do
    @deck.deck_cards.destroy_all

    new_deck = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_equal 0, new_deck.deck_cards.count
  end

  # A duplicate of a TEF-CRI deck is still a TEF-CRI deck; it must not slide onto
  # whatever pool happens to be current.
  test "the copy keeps the source deck's standard pool" do
    source = decks(:one)
    source.update!(format: "standard", standard_pool: standard_pools(:twm_asc))

    copy = Decks::Duplicator.call(source, user: source.user)

    assert_equal standard_pools(:twm_asc), copy.standard_pool
  end

  # A version records a list that was played; the copy has played nothing yet.
  test "the copy carries none of the source's versions" do
    assert @deck.deck_versions.exists?, "sanity: the fixture deck has a version"

    copy = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_empty copy.deck_versions
  end

  # No fixture deck carries an archetype, so nil copying to nil proves nothing.
  test "the owner's copy keeps the archetype" do
    @deck.update!(archetype: archetypes(:ogerpon))

    copy = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_equal archetypes(:ogerpon), copy.archetype
  end

  # The columns default to false and no fixture sets them, so the owner half has to be asserted
  # too, or "copied" and "never copied" would produce the same row.
  test "the owner's copy keeps how the deck is played" do
    @deck.update!(physical: true, tcg_live: true)

    copy = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_predicate copy, :physical?
    assert_predicate copy, :tcg_live?
  end

  # The one path where copying owned_copies would pass validation: a physical copy of a deck
  # whose rows are really backed.
  test "the owner's copy of a physical deck starts fully proxied" do
    @deck.update!(physical: true)
    @deck.user.collections.find_or_create_by!(card: cards(:honedge)).update!(quantity: 2)
    @deck.deck_cards.find_by!(card: cards(:honedge)).update!(owned_copies: 2)
    # setup loaded the association before this row was backed; without the reload the service
    # reads the stale 0 and a Duplicator copying owned_copies would stay green.
    @deck.reload

    copy = Decks::Duplicator.call(@deck, user: @deck.user)

    assert_predicate copy, :physical?
    assert_equal [ 0 ], copy.deck_cards.pluck(:owned_copies).uniq
  end

  test "the owner's copy of a shared deck is private" do
    @deck.update!(shared: true)

    copy = Decks::Duplicator.call(@deck, user: @deck.user)

    refute_predicate copy, :shared?
  end

  test "a shared deck copied by another member is theirs, private, and keeps its name verbatim" do
    reader = users(:two)
    @deck.update!(shared: true)

    assert_difference -> { reader.decks.count }, 1 do
      assert_no_difference -> { @deck.user.decks.count } do
        @copy = Decks::Duplicator.call(@deck, user: reader)
      end
    end

    assert_equal reader, @copy.user
    assert_equal "Original", @copy.name
    refute_predicate @copy, :shared?
  end

  # The request names what to take — name, format, archetype, list — and a description is the
  # author's notes; `physical` and `tcg_live` say how *the author* plays the deck.
  test "a stranger's copy leaves the author's description and play flags behind" do
    @deck.update!(shared: true, physical: true, tcg_live: true)

    copy = Decks::Duplicator.call(@deck, user: users(:two))

    assert_nil copy.description
    refute_predicate copy, :physical?
    refute_predicate copy, :tcg_live?
  end

  test "a stranger's copy keeps the archetype" do
    @deck.update!(shared: true, archetype: archetypes(:ogerpon))

    copy = Decks::Duplicator.call(@deck, user: users(:two))

    assert_equal archetypes(:ogerpon), copy.archetype
  end

  # Every fixture is Standard on twm_por, which is also the column default: dropping `format:`
  # would stay green on them.
  test "a stranger's copy keeps a non-Standard format and its name" do
    @deck.update!(shared: true, format: "other", other_format_name: "Gym Leader Challenge", standard_pool: nil)

    copy = Decks::Duplicator.call(@deck, user: users(:two))

    assert_predicate copy, :other?
    assert_equal "Gym Leader Challenge", copy.other_format_name
    assert_nil copy.standard_pool
  end

  test "a stranger's copy keeps the Standard pool rather than the current one" do
    @deck.update!(shared: true, standard_pool: standard_pools(:twm_asc))

    copy = Decks::Duplicator.call(@deck, user: users(:two))

    assert_predicate copy, :standard?
    assert_equal standard_pools(:twm_asc), copy.standard_pool
  end

  # Two printings of one card are two rows, and the copy must not fold them by fingerprint.
  test "a stranger's copy keeps each printing as its own row" do
    honedge = cards(:honedge)
    reprint = Card.create!(
      name: honedge.name, card_type: "Pokémon", hp: honedge.hp, type_symbol: honedge.type_symbol,
      retreat_cost: honedge.retreat_cost, stage: honedge.stage,
      card_set: card_sets(:asc), set_name: "ASC", set_number: "99", rarity: "Common"
    )
    reprint.update_column(:fingerprint, honedge.fingerprint)
    @deck.update!(shared: true)
    @deck.deck_cards.destroy_all
    @deck.deck_cards.create!(card: honedge, quantity: 2)
    @deck.deck_cards.create!(card: reprint, quantity: 1)

    copy = Decks::Duplicator.call(@deck, user: users(:two))

    assert_equal [ [ honedge.id, 2 ], [ reprint.id, 1 ] ].sort,
                 copy.deck_cards.map { |dc| [ dc.card_id, dc.quantity ] }.sort
  end

  test "a field list's copy belongs to the reader, private, under its own name" do
    field_list = decks(:field_list)

    copy = Decks::Duplicator.call(field_list, user: users(:one))

    assert_equal users(:one), copy.user
    assert_equal "Ash Ketchum — Regional Championship (2026-03-14)", copy.name
    refute_predicate copy, :shared?
  end

  # decks.archetype_id on a field list is the detector's guess at import, and contradicts the
  # standing on 512 of 1798 in development. The column is set here so that a reversed
  # precedence — the column first, then the standing — would answer ogerpon.
  test "a field list's copy takes its standing's archetype over its own column" do
    field_list = decks(:field_list)
    field_list.update_column(:archetype_id, archetypes(:ogerpon).id)
    tournament_standings(:ash_masters).update!(deck: field_list)

    copy = Decks::Duplicator.call(field_list, user: users(:one))

    assert_equal archetypes(:standings_marker), copy.archetype
  end

  test "a field list with no standing falls back to its own column" do
    field_list = decks(:field_list)
    field_list.update_column(:archetype_id, archetypes(:ogerpon).id)
    assert TournamentStanding.where(deck: field_list).none?, "sanity: no standing lists this deck"

    copy = Decks::Duplicator.call(field_list, user: users(:one))

    assert_equal archetypes(:ogerpon), copy.archetype
  end

  # index_tournament_standings_on_deck_id is not unique. The oldest standing is the one whose
  # import created the list; swapping the archetypes proves the rule is the id and not row order.
  test "when two standings list one deck, the oldest decides" do
    field_list = decks(:field_list)
    older, newer = tournament_standings(:ash_masters, :giovanni_masters).sort_by(&:id)
    other = Archetype.create!(name: "Second marker", primary_card: cards(:doublade))
    older.update!(deck: field_list)
    newer.update!(deck: field_list, archetype: other)

    assert_equal archetypes(:standings_marker), Decks::Duplicator.call(field_list, user: users(:one)).archetype

    older.update!(archetype: other)
    newer.update!(archetype: archetypes(:standings_marker))

    assert_equal other, Decks::Duplicator.call(field_list, user: users(:one)).archetype
  end
end
