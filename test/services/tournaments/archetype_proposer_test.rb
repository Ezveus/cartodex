require "test_helper"

# The proposer answers "which archetype is this Limitless deck", and it only ever *proposes*: an
# admin confirms every answer once per deck reference, and the confirmed one is what gets stored.
#
# The catalogue these tests build is a stand-in, not a copy: the verdicts measured on 2026-09-22
# were taken against 81 real archetypes and real lists off event 577, and
# test/fixtures/archetypes.yml holds three rows. Each test therefore builds the smallest catalogue
# that reproduces one measured case and says which case it is standing in for.
class Tournaments::ArchetypeProposerTest < ActiveSupport::TestCase
  setup do
    @next_number = 1
  end

  # Archetype#name is derived from the member cards unless `custom_name` says otherwise, so every
  # archetype here passes it: without it the name a test writes is silently discarded and the whole
  # discriminator these tests are about — the *name* — is the one the model made up.

  # Measured: `Slowking` was filed as *Lillie's Clefairy ex* on two rows, because a rule-box tech
  # card in the list scores 3 against Slowking's 2. The detector's ranking is what gets this wrong,
  # and the deck's own published name is what gets it right — which is the whole reason the
  # proposer exists rather than a call to Decks::ArchetypeDetector.
  test "the published deck name outranks the score, which is the measured Slowking regression" do
    slowking = pokemon("Slowking")
    clefairy = pokemon("Lillie's Clefairy ex", rule_box: true)
    slowking_archetype = Archetype.create!(primary_card: slowking, name: "Slowking", custom_name: true)
    clefairy_archetype = Archetype.create!(primary_card: clefairy, name: "Lillie's Clefairy ex", custom_name: true)

    proposal = propose("Slowking", slowking, clefairy)

    assert_equal :decided, proposal.verdict
    assert_equal slowking_archetype, proposal.archetype
    # Both are genuine candidates — containment is unchanged — and the score alone still prefers
    # the wrong one, which is what makes the assertion above mean something.
    assert_equal [ slowking_archetype, clefairy_archetype ].to_set, proposal.candidates.to_set
    assert_equal clefairy_archetype, detected_on_a_deck_of(slowking, clefairy)
  end

  # Measured: `Dhelmise` sits between *Dhelmise / Banette* and *Dhelmise / Sinistcha*, tied at
  # overlap 1 and score 4. Decks::ArchetypeDetector's own max_by settles that on whichever row the
  # database returned first, so one list is filed under either archetype on two runs. Here it is
  # refused instead, and the admin picks.
  test "two candidates tied on both name overlap and score are ambiguous, never a winner" do
    dhelmise = pokemon("Dhelmise")
    banette = pokemon("Banette")
    sinistcha = pokemon("Sinistcha")
    with_banette = Archetype.create!(primary_card: dhelmise, secondary_card: banette,
      name: "Dhelmise / Banette", custom_name: true)
    with_sinistcha = Archetype.create!(primary_card: dhelmise, secondary_card: sinistcha,
      name: "Dhelmise / Sinistcha", custom_name: true)

    proposal = propose("Dhelmise", dhelmise, banette, sinistcha)

    assert_equal :ambiguous, proposal.verdict
    assert_nil proposal.archetype
    assert_equal [ with_banette, with_sinistcha ].to_set, proposal.candidates.to_set
  end

  # `Basic Box` and `Tera Box` are Limitless's words for "no single deck name fits" — 9 of the 96
  # measured rows — and cartodex has archetypes with `Box` in their names. Kept as a token, the
  # word alone decides one of them, which is the wrong answer arrived at confidently.
  test "a name that overlaps nothing decides nothing, with two candidates" do
    charizard = pokemon("Charizard ex", rule_box: true)
    toxtricity = pokemon("Toxtricity")
    Archetype.create!(primary_card: charizard, name: "Charizard ex", custom_name: true)
    Archetype.create!(primary_card: toxtricity, name: "Toxtricity Box", custom_name: true)

    proposal = propose("Basic Box", charizard, toxtricity)

    assert_equal :name_says_nothing, proposal.verdict
    assert_nil proposal.archetype
    assert_equal 2, proposal.candidates.size
  end

  # The same verdict with exactly **one** candidate, and it is a separate test because it is the
  # case a `return :decided if candidates.one?` short-circuit gets wrong while passing everything
  # else on this page. Silently, into a public wiki sheet.
  test "a name that overlaps nothing decides nothing, with exactly one candidate" do
    charizard = pokemon("Charizard ex", rule_box: true)
    only = Archetype.create!(primary_card: charizard, name: "Charizard ex", custom_name: true)

    proposal = propose("Tera Box", charizard)

    assert_equal :name_says_nothing, proposal.verdict
    assert_nil proposal.archetype
    assert_equal [ only ], proposal.candidates
  end

  # Measured: `Marnie's Grimmsnarl` has no candidate at all, because the list plays no Froslass and
  # the only Grimmsnarl archetype in the catalogue names one. A missing secondary disqualifies —
  # it names a pairing the deck is not playing — so this is a refusal and not a near miss.
  test "containment finding nothing is a refusal of its own" do
    grimmsnarl = pokemon("Marnie's Grimmsnarl ex", rule_box: true)
    froslass = pokemon("Froslass")
    Archetype.create!(primary_card: grimmsnarl, secondary_card: froslass,
      name: "Marnie's Grimmsnarl ex / Froslass", custom_name: true)

    proposal = propose("Marnie's Grimmsnarl", grimmsnarl)

    assert_equal :no_candidate, proposal.verdict
    assert_nil proposal.archetype
    assert_empty proposal.candidates
  end

  # The one thing the proposer may not do is re-implement containment: four clauses that can each
  # be got subtly wrong, and a copy that diverged on any of them would still satisfy a test
  # written against one of them. So this asserts the *set*, over a catalogue that exercises three
  # of the four at once — and over a list that names a **second printing** of a member card, which
  # is what a resolver handing card ids rather than fingerprints to the detector gets wrong.
  test "the candidate set is the detector's, over a list holding another printing of a member" do
    charizard_a = pokemon("Charizard ex", rule_box: true)
    charizard_b = pokemon("Charizard ex", rule_box: true, set_name: "TS2")
    budew = pokemon("Budew")
    munkidori = pokemon("Munkidori")
    assert_equal charizard_a.fingerprint, charizard_b.fingerprint,
      "two printings of one card must share a fingerprint for this test to mean anything"

    # Named on the printing the list does *not* hold.
    contained = Archetype.create!(primary_card: charizard_a, name: "Charizard ex", custom_name: true)
    pair = Archetype.create!(primary_card: charizard_a, secondary_card: budew,
      name: "Budew / Charizard", custom_name: true)
    # Its secondary is absent from the list, so containment disqualifies it outright.
    Archetype.create!(primary_card: charizard_a, secondary_card: munkidori,
      name: "Munkidori / Charizard", custom_name: true)

    proposal = propose("Charizard Budew", charizard_b, budew)

    assert_equal [ contained, pair ].to_set, proposal.candidates.to_set
    # The same list built as a Deck and run through the detector agrees about containment: the
    # two answer one question, and only the ranking is the proposer's own.
    assert_equal pair, detected_on_a_deck_of(charizard_b, budew)
  end

  # A reference the catalogue does not hold is not an error and not a scrape — Cards::Printings'
  # rule. It simply is not a fingerprint, and a list of nothing but unknown printings has no
  # candidate rather than every candidate.
  test "resolves the list against the catalogue alone and never fetches" do
    charizard = pokemon("Charizard ex", rule_box: true)
    Archetype.create!(primary_card: charizard, name: "Charizard ex", custom_name: true)

    proposal = Tournaments::ArchetypeProposer.call(
      list_text: "4 Nothing At All ZZ9 404\n2 Charizard ex #{charizard.set_name} #{charizard.set_number}",
      label: "Charizard ex", archetypes: Archetype.all
    )

    assert_equal :decided, proposal.verdict

    empty = Tournaments::ArchetypeProposer.call(
      list_text: "4 Nothing At All ZZ9 404", label: "Anything", archetypes: Archetype.all
    )
    assert_equal :no_candidate, empty.verdict
  end

  # The archetypes are passed in rather than read from the database, because the preview proposes
  # for 45 deck references in one web request off one catalogue.
  test "looks only at the archetypes it was handed" do
    charizard = pokemon("Charizard ex", rule_box: true)
    Archetype.create!(primary_card: charizard, name: "Charizard ex", custom_name: true)

    proposal = Tournaments::ArchetypeProposer.call(
      list_text: list_text_for(charizard), label: "Charizard ex",
      archetypes: Archetype.where(id: archetypes(:ogerpon))
    )

    assert_equal :no_candidate, proposal.verdict
  end

  # The spelling that made `mega` a stop word: cartodex calls a deck "Mega Lucario ex / Hariyama"
  # where Limitless calls it "Lucario Hariyama", and calls another one "Mega Absol Box". Kept as a
  # token, `mega` alone lifts the Lucario archetype to the same overlap as the Absol one, where its
  # far higher score then wins — a confident answer naming a deck that shares nothing with the
  # label but the word "Mega".
  test "drops the words that would match every Mega archetype against every Mega deck name" do
    lucario = pokemon("Mega Lucario ex", rule_box: true)
    hariyama = pokemon("Hariyama")
    absol = pokemon("Absol")
    Archetype.create!(primary_card: lucario, secondary_card: hariyama,
      name: "Mega Lucario ex / Hariyama", custom_name: true)
    absol_archetype = Archetype.create!(primary_card: absol, name: "Absol", custom_name: true)

    proposal = propose("Mega Absol Box", lucario, hariyama, absol)

    assert_equal :decided, proposal.verdict
    assert_equal absol_archetype, proposal.archetype
  end

  # Tokens under three characters go because of the possessive: `Marnie's Grimmsnarl` and
  # `Ethan's Typhlosion ex` both tokenise to a bare `s`, which is an overlap of 1 between two decks
  # that share nothing — and an overlap of 1 is all it takes, since the containment score then
  # settles the tie in favour of whichever archetype plays the most rule-box Pokémon.
  test "a possessive apostrophe is not an overlap" do
    typhlosion = pokemon("Ethan's Typhlosion ex", rule_box: true)
    grimmsnarl = pokemon("Grimmsnarl")
    Archetype.create!(primary_card: typhlosion, name: "Ethan's Typhlosion ex", custom_name: true)
    grimmsnarl_archetype = Archetype.create!(primary_card: grimmsnarl, name: "Grimmsnarl", custom_name: true)

    proposal = propose("Marnie's Grimmsnarl", typhlosion, grimmsnarl)

    assert_equal :decided, proposal.verdict
    assert_equal grimmsnarl_archetype, proposal.archetype
  end

  private

  def propose(label, *cards)
    Tournaments::ArchetypeProposer.call(
      list_text: cards.map { |card| list_text_for(card) }.join("\n"),
      label: label,
      archetypes: Archetype.all
    )
  end

  def list_text_for(card) = "4 #{card.name} #{card.set_name} #{card.set_number}"

  # What Decks::ArchetypeDetector on its own would have answered for the same list, which is the
  # answer several of these tests exist to be different from.
  def detected_on_a_deck_of(*cards)
    deck = decks(:one)
    deck.deck_cards.destroy_all
    cards.each { |card| deck.deck_cards.create!(card: card, quantity: 2) }

    Decks::ArchetypeDetector.call(deck.reload).archetype
  end

  def pokemon(name, rule_box: false, set_name: "TST")
    Card.create!(
      name: name, card_type: "Pokémon", set_name: set_name, set_number: (@next_number += 1).to_s,
      rarity: "Rare", hp: 120, type_symbol: "Psychic", retreat_cost: 1,
      pokemon_subtype: rule_box ? pokemon_subtypes(:pokemon_ex) : nil
    )
  end
end
