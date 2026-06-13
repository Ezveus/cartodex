# Infers the most likely Archetype for a deck from its Pokémon line-up.
#
# The "notable" Pokémon of a deck are its rule-box attackers (ex / V / VMAX…),
# ranked ahead of the rest, then by HP and copies played. The top one or two
# names drive the detection:
#
#   * If an existing Archetype is built from those Pokémon, it is returned as a
#     match (preferring a two-Pokémon archetype over a single-Pokémon one).
#   * Otherwise the deck's own candidate cards are returned so the caller can
#     pre-fill a "create archetype" form.
#
# Returns a Result responding to #archetype, #primary and #secondary.
class Decks::ArchetypeDetector < ApplicationService
  Result = Struct.new(:archetype, :primary, :secondary, keyword_init: true) do
    def matched? = archetype.present?
  end

  def initialize(deck)
    @deck = deck
  end

  def call
    candidates = notable_pokemon
    return Result.new if candidates.empty?

    primary, secondary = candidates.first(2)

    Result.new(
      archetype: match_existing(candidates),
      primary: primary,
      secondary: secondary
    )
  end

  private

  # Distinct Pokémon cards, most representative first.
  def notable_pokemon
    pokemon = @deck.deck_cards.select { |dc| dc.card&.card_type == "Pokémon" }

    pokemon
      .sort_by { |dc| [ dc.card.pokemon_subtype&.rule_box ? 0 : 1, -dc.card.hp.to_i, -dc.quantity ] }
      .map(&:card)
      .uniq(&:name)
  end

  # Looks for an archetype assembled from the candidate Pokémon, favouring the
  # richest match (two Pokémon over one). Matching is by name so the archetype
  # can reference a different printing of the same Pokémon than the deck does.
  def match_existing(candidates)
    names = candidates.map(&:name)

    Archetype
      .joins(:primary_pokemon)
      .left_joins(:secondary_pokemon)
      .where(cards: { name: names })
      .includes(:primary_pokemon, :secondary_pokemon)
      .map { |archetype| [ archetype, score_archetype(archetype, names) ] }
      .select { |(_, score)| score.positive? }
      .max_by { |(_, score)| score }
      &.first
  end

  # A two-Pokémon archetype scores higher than a single-Pokémon one, but only
  # when both of its Pokémon are present in the deck; otherwise it is disqualified.
  def score_archetype(archetype, names)
    secondary_name = archetype.secondary_pokemon&.name
    return 0 if secondary_name && names.exclude?(secondary_name)

    secondary_name ? 2 : 1
  end
end
