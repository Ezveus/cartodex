require "test_helper"

# The suggester proposes; a human decides. Every test here is about that asymmetry rather than
# about coverage: measured on the production dump, the rules label 33 of the 51 Trainer/Energy
# fingerprints the recorded lists play and 13 of the 43 Pokémon ones, and they get
# *Telepathic Psychic Energy* wrong while missing Pokégear 3.0 and Professor Turo's Scenario.
# A rule that could be trusted alone would not need the `curated` source at all.
class CardLabels::RoleSuggesterTest < ActiveSupport::TestCase
  setup do
    @roles = CardLabel::ROLES.to_h do |attributes|
      [ attributes[:slug], CardLabel.create!(family: "role", **attributes) ]
    end
  end

  test "it suggests a role from the card's own effect text" do
    card = trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")

    result = CardLabels::RoleSuggester.call

    assignment = @roles["search"].assignments.sole

    assert_equal card.fingerprint, assignment.fingerprint
    assert_equal "suggested", assignment.source
    assert_not assignment.rejected
    assert_equal card.id, assignment.card_id
    assert_equal 1, result.created
  end

  # The half of the vocabulary that makes roles work on Pokémon at all: a Basic whose attack
  # fetches two Basics is doing a search Item's job, and `cards.effect` is empty on every Pokémon
  # in the catalogue. Reading only that column would leave every Pokémon unlabelled and make
  # "No role recorded" a statement about the parser rather than about the card.
  test "it reads a Pokémon's attacks and abilities, not only its effect" do
    pokemon = Card.create!(name: "Lumineon V", card_type: "Pokémon", set_name: "BRS", set_number: "40",
                           rarity: "Ultra Rare", hp: 170, type_symbol: "Water", retreat_cost: 1,
                           stage: "Basic")
    pokemon.abilities.create!(name: "Luminous Sign",
                              effect: "Search your deck for a Supporter card, reveal it, and put it into your hand.",
                              position: 0)

    CardLabels::RoleSuggester.call

    assert_equal [ pokemon.fingerprint ], @roles["search"].assignments.pluck(:fingerprint)
  end

  # A label is about the card, not the printing, so two printings of one card are one decision —
  # and the UNIQUE key on (card_label_id, fingerprint) would raise rather than write a second.
  test "one suggestion per fingerprint, however many printings carry it" do
    first = trainer("Switch", "Switch your Active Pokémon with 1 of your Benched Pokémon.", number: "1")
    second = trainer("Switch", "Switch your Active Pokémon with 1 of your Benched Pokémon.", number: "2")

    assert_equal first.fingerprint, second.fingerprint

    result = CardLabels::RoleSuggester.call

    assert_equal 1, @roles["switch"].assignments.count
    assert_equal 1, result.created
  end

  # The central rule of the store. A human's yes and a human's no are both decisions, and a run
  # six weeks later must leave each of them exactly where it found it — a suggester that rewrote
  # a refusal would re-propose Iono as a Gust every time it ran.
  test "it never examines a pair a human has decided" do
    card = trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    decided = @roles["search"].assignments.create!(fingerprint: card.fingerprint, source: "curated",
                                                   rejected: true)

    result = CardLabels::RoleSuggester.call

    assert_equal decided.attributes.except("updated_at"),
      decided.reload.attributes.except("updated_at")
    assert_equal 1, @roles["search"].assignments.count
    assert_equal 0, result.created
    assert_equal 1, result.decided
  end

  # Defensive rather than reachable: CardLabels::Importer only ever writes `type` labels today.
  # It is the same rule as above read from the other side — the suggester owns `suggested` rows
  # and nothing else — and it is what stops a future role importer and this service fighting.
  test "it never touches an imported row" do
    card = trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    imported = @roles["search"].assignments.create!(fingerprint: card.fingerprint, source: "imported")

    result = CardLabels::RoleSuggester.call

    assert_equal "imported", imported.reload.source
    assert_equal 0, result.created
    assert_equal 1, result.decided
  end

  # The one deletion in the whole feature, and it is the machine deleting its own opinion: a
  # `suggested` row no rule stands behind any more would show the curation screen a proposal
  # nothing proposes.
  test "a suggestion whose rule no longer matches is withdrawn" do
    card = trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    stale = @roles["gust"].assignments.create!(fingerprint: card.fingerprint, source: "suggested")

    result = CardLabels::RoleSuggester.call

    assert_not CardLabelAssignment.exists?(stale.id)
    assert_equal 1, result.withdrawn
    assert_equal 1, @roles["search"].assignments.count
  end

  # The union, and the only test that can tell it from reading one printing: a Trainer's
  # fingerprint is a hash of its name alone, so two printings of it may in principle carry
  # differently worded text. Measured on the production dump, 193 Trainer/Energy fingerprints hold
  # several printings and 0 of them disagree — so this is the hedge stated as a rule rather than a
  # fix for something observed, and without it a reprint whose text was scraped short would
  # withdraw a role on the next run.
  test "a fingerprint is read from every printing that carries it, not from one" do
    silent = trainer("Nest Ball", "", number: "10")
    worded = trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.",
                     number: "11")

    assert_equal silent.fingerprint, worded.fingerprint

    CardLabels::RoleSuggester.call

    assert_equal [ worded.fingerprint ], @roles["search"].assignments.pluck(:fingerprint)
  end

  # A card with no fingerprint cannot be labelled at all: the assignment would name a key no card
  # carries and the report could never join it. It stays visible and unlabelled, which is the
  # arbitration CardStats::GROUPING_KEY already makes for the same card.
  test "a card with no fingerprint is skipped and counted" do
    card = trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    card.update_column(:fingerprint, nil)

    result = CardLabels::RoleSuggester.call

    assert_equal 0, CardLabelAssignment.count
    # Counted over the whole catalogue, not over this one card: three fixtures carry no
    # fingerprint either (fixtures skip the before_save that computes it), and a literal 1 here
    # would be a statement about the fixture file rather than about the rule.
    assert_equal Card.where(fingerprint: [ nil, "" ]).count, result.unfingerprinted
  end

  # The withdrawal runs over the pairs the rules *stopped* matching, which is a different branch
  # from every provenance test above — those all sit on pairs the rules do match. A `where` that
  # forgot its `suggested` scope would delete a human's refusal here and nothing else would say so.
  test "withdrawal deletes only the machine's own rows" do
    card = trainer("Bravery Charm", "The Basic Pokémon this card is attached to gets +50 HP.")
    refusal = @roles["gust"].assignments.create!(fingerprint: card.fingerprint, source: "curated",
                                                 rejected: true)
    imported = @roles["draw"].assignments.create!(fingerprint: card.fingerprint, source: "imported")
    stale = @roles["search"].assignments.create!(fingerprint: card.fingerprint, source: "suggested")

    result = CardLabels::RoleSuggester.call

    assert CardLabelAssignment.exists?(refusal.id)
    assert CardLabelAssignment.exists?(imported.id)
    assert_not CardLabelAssignment.exists?(stale.id)
    assert_equal 1, result.withdrawn
  end

  # Six weeks later, with the catalogue moved: a rule that starts matching a card adds its role and
  # leaves the rest of that card alone. Only reachable for Trainers and Energy, whose fingerprint is
  # a hash of the name and therefore survives a text change — a Pokémon's would move, which is the
  # resync task's subject rather than this one's.
  test "a rule that starts matching adds its role and disturbs nothing else" do
    card = trainer("Iono", "Each player shuffles their hand and draws a card for each Prize card.")
    CardLabels::RoleSuggester.call
    draw = @roles["draw"].assignments.sole

    card.update!(effect: "#{card.effect} Search your deck for a Supporter card.")
    result = CardLabels::RoleSuggester.call

    assert_equal 1, result.created
    assert_equal draw.id, @roles["draw"].assignments.sole.id
    assert_equal [ card.fingerprint ], @roles["search"].assignments.pluck(:fingerprint)
  end

  # A role can only lose its rule by a code change, since the seed never deletes and the admin
  # panel refuses to. When it does, the label row survives with its assignments — and a human's
  # decisions are theirs to keep, while the machine's proposals are no longer maintainable by
  # anything: nothing will ever withdraw them, and the report would carry a section built on
  # guesses no rule still makes.
  test "a role whose rule has gone keeps its decisions and loses its suggestions" do
    card = trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    orphan = CardLabel.create!(family: "role", slug: "mill", name: "Mill", position: 80)
    decision = orphan.assignments.create!(fingerprint: card.fingerprint, source: "curated")
    guess = orphan.assignments.create!(fingerprint: cards(:doublade).fingerprint, source: "suggested")

    CardLabels::RoleSuggester.call

    assert CardLabelAssignment.exists?(decision.id)
    assert_not CardLabelAssignment.exists?(guess.id)
  end

  # The §9.6 question, asked of this service: what does the second run do? Nothing, and it says
  # nothing — the receipt an admin reads must not report work that did not happen.
  test "a second run creates nothing and withdraws nothing" do
    trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    CardLabels::RoleSuggester.call

    assert_no_difference "CardLabelAssignment.count" do
      @result = CardLabels::RoleSuggester.call
    end

    assert_equal 0, @result.created
    assert_equal 0, @result.withdrawn
    assert_equal 1, @result.kept
  end

  # One line of real card text per rule, so that every rule in the vocabulary is exercised by
  # something rather than by the two or three a behavioural test happens to reach. Written after
  # three rules were rewritten in /x form, lost their literal spaces, wrote 0 rows against a
  # measured 34, 45 and 58 on the production dump — and left the whole suite green.
  RULE_SAMPLES = {
    "draw" => "Each player shuffles their hand into their deck and draws 4 cards.",
    "search" => "Search your deck for a Basic Pokémon and put it onto your Bench.",
    "gust" => "Switch in 1 of your opponent's Benched Pokémon to the Active Spot.",
    "switch" => "Switch your Active Pokémon with 1 of your Benched Pokémon.",
    "recovery" => "Put up to 2 Basic Energy cards from your discard pile into your hand.",
    "disruption" => "Your opponent discards cards from their hand until they have 3 cards in their hand.",
    "energy-acceleration" => "Choose up to 2 of your Benched Pokémon and attach a Basic Energy card " \
                             "from your discard pile to each of them."
  }.freeze

  test "every rule in the vocabulary proposes its own role on real card text" do
    RULE_SAMPLES.each_with_index do |(slug, effect), index|
      trainer("Sample #{slug}", effect, number: (100 + index).to_s)
    end

    CardLabels::RoleSuggester.call

    RULE_SAMPLES.each_key do |slug|
      assert_predicate @roles[slug].assignments, :any?, "#{slug} proposed nothing for its own sample"
    end
  end

  # The catalogue is read before the write lock is taken, not under it. serialized_transaction is
  # a SQLite BEGIN IMMEDIATE: measured on the production dump, the reading half is 543 ms of a
  # 1239 ms run, and inside the transaction that is 543 ms of every other writer waiting on a 5 s
  # busy timeout for a service that is only looking. The depth is recorded at the read rather than
  # asserted afterwards, the way StandingsImporterTest records it at each simulated fetch.
  class DepthRecordingSuggester < CardLabels::RoleSuggester
    attr_reader :depth_at_read

    private

    def load_cards
      @depth_at_read ||= ActiveRecord::Base.connection.open_transactions
      super
    end
  end

  test "the catalogue is read before the write lock is taken" do
    trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    suggester = DepthRecordingSuggester.new
    outside = ActiveRecord::Base.connection.open_transactions

    suggester.call

    assert_equal outside, suggester.depth_at_read,
      "the catalogue was read inside the transaction, holding SQLite's write lock for it"
  end

  # Every rule names a role by slug, so a database whose vocabulary has not been seeded would
  # have the run write some rules' rows and drop the rest — a partial suggestion nothing reports.
  # It refuses before writing anything instead.
  test "a vocabulary the database has not seeded is refused before anything is written" do
    trainer("Nest Ball", "Search your deck for a Basic Pokémon and put it onto your Bench.")
    @roles["gust"].destroy!

    # Not wrapped in assert_no_difference: Rails runs that block through
    # _assert_nothing_raised_or_warn, which re-raises anything it catches as a
    # Minitest::UnexpectedError — a Minitest::Assertion, which assert_raises re-raises rather than
    # matching, so the nested form reports the refusal as an error and the test can never pass.
    error = assert_raises(CardLabels::RoleSuggester::MissingRoles) { CardLabels::RoleSuggester.call }

    assert_equal 0, CardLabelAssignment.count
    assert_match "gust", error.message
  end

  # Every slug a rule proposes has to exist in the vocabulary the seed writes, and every role the
  # vocabulary offers has to be proposable — a rule with no row can never be written, and a row
  # with no rule is a checkbox that only a human can ever tick. Neither is wrong on its own; both
  # are decisions, so they are stated here rather than discovered on the curation screen.
  test "the rules and the vocabulary name the same roles" do
    assert_equal CardLabel::ROLES.map { |role| role[:slug] }.sort,
      CardLabels::RoleSuggester::RULES.keys.sort
  end

  private

  def trainer(name, effect, number: "1")
    Card.create!(name: name, card_type: "Trainer", subtype: "Item", set_name: "TST",
                 set_number: number, rarity: "Common", effect: effect)
  end
end
