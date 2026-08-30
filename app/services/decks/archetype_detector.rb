# Infers the Archetype of a deck, and — separately — suggests what a new one
# should be built from. Those are two jobs with different false-positive risks,
# so they answer different questions from different inputs:
#
#   * Matching asks whether an existing Archetype's member cards are all in this
#     deck. Those members were chosen by a human, so containment is safe to ask
#     of the whole card pool, whatever the type. A false positive can only come
#     from a badly defined archetype, which is a data problem.
#   * Suggestion ranks the deck's own notable *Pokémon* to pre-fill a "create
#     archetype" form. Ranking Trainers by copies played would propose Iono,
#     Professor's Research and Ultra Ball on every deck ever imported, so it
#     stays Pokémon-only. A Trainer-led archetype is created by hand; once it
#     exists, matching finds it on its own.
#
# Returns a Result responding to #archetype, #suggested_primary and #suggested_secondary.
class Decks::ArchetypeDetector < ApplicationService
  Result = Struct.new(:archetype, :suggested_primary, :suggested_secondary, keyword_init: true) do
    def matched? = archetype.present?
  end

  # How much a member identifies a deck. The sum is the archetype's score, so
  # Gardevoir ex / Munkidori scores 6, Gardevoir ex alone 3, Lost Zone Box
  # (Comfey / Colress's Experiment) 3, and an ill-advised "Iono" archetype 1 —
  # it can only win when nothing else matches at all.
  RULE_BOX_WEIGHT = 3
  POKEMON_WEIGHT = 2
  OTHER_WEIGHT = 1

  def initialize(deck)
    @deck = deck
  end

  def call
    primary, secondary = notable_pokemon.first(2)

    Result.new(
      archetype: match_existing,
      suggested_primary: primary,
      suggested_secondary: secondary
    )
  end

  private

  # Distinct Pokémon cards, most representative first. Suggestion only.
  def notable_pokemon
    pokemon = @deck.deck_cards.select { |dc| dc.card&.card_type == "Pokémon" }

    pokemon
      .sort_by { |dc| [ dc.card.pokemon_subtype&.rule_box ? 0 : 1, -dc.card.hp.to_i, -dc.quantity ] }
      .map(&:card)
      .uniq(&:name)
  end

  # Every card in the deck, keyed on Card#fingerprint — the "same card, any
  # printing" key. Strictly more correct than the name matching it replaces,
  # which conflated unrelated cards that happen to share one.
  def deck_fingerprints
    @deck.deck_cards.filter_map { |dc| dc.card&.fingerprint }.uniq
  end

  # `preload` rather than `includes`: the WHERE clause already references `cards`
  # through the join on the primary, and letting Rails pick eager_load would make
  # it alias that same table twice for the two associations. preload always issues
  # separate queries, so there is nothing to alias.
  def match_existing
    fingerprints = deck_fingerprints
    return nil if fingerprints.empty?

    Archetype
      .joins(:primary_card)
      .where(cards: { fingerprint: fingerprints })
      .preload(primary_card: :pokemon_subtype, secondary_card: :pokemon_subtype)
      .map { |archetype| [ archetype, score(archetype, fingerprints) ] }
      .select { |(_, score)| score.positive? }
      .max_by { |(archetype, score)| [ score, member_count(archetype) ] }
      &.first
  end

  # Zero disqualifies. A secondary absent from the deck rules the archetype out
  # entirely rather than costing it points: it names a pairing the deck is not playing.
  def score(archetype, fingerprints)
    members = [ archetype.primary_card, archetype.secondary_card ].compact
    return 0 unless members.all? { |card| fingerprints.include?(card.fingerprint) }

    members.sum { |card| weight(card) }
  end

  def weight(card)
    return OTHER_WEIGHT unless card.card_type == "Pokémon"

    card.pokemon_subtype&.rule_box ? RULE_BOX_WEIGHT : POKEMON_WEIGHT
  end

  # Breaks a tie on the score — a Pokémon + Trainer pair and a lone rule-box
  # Pokémon both score 3, and the richer description should win, which is what
  # the old two-beats-one rule meant.
  def member_count(archetype)
    archetype.secondary_card_id ? 2 : 1
  end
end
