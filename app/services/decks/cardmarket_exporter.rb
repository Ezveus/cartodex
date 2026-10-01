class Decks::CardmarketExporter < ApplicationService
  TERA_ABILITY = "Tera".freeze
  NOTHING_TO_BUY = "Nothing to buy — every card is owned".freeze

  # The trailing printing code of a product slug: "PAL172", "CRZGG11", "SV1en166", "SVEen001",
  # and occasionally a bare "SVP" or "SV1en". Never a version tag, which a few slugs end on
  # because they carry no code at all ("Fog-Crystal-V1").
  PRINTING_CODE = /-(?!V\d+\z)[A-Z][A-Z0-9]*(?:en)?\d*\z/

  # `missing_only:` asks only for the copies the member still has to buy (#208): on a physical
  # deck that is each row's proxies, netting off the real copies it already backs. Free copies
  # in the collection and other printings are deliberately not netted off — backing is not
  # re-derived here, and owning an equivalent printing is the printing swap's business.
  def initialize(deck, missing_only: false)
    @deck = deck
    @missing_only = missing_only
  end

  # Nothing to list answers "" rather than a lone newline, so a caller can tell "nothing to buy"
  # from a list.
  def call
    deck_cards = @deck.deck_cards.includes(card: [ :attacks, :abilities ]).order("cards.name")
    lines = deck_cards.filter_map do |dc|
      quantity = wanted(dc)
      card_line(dc, quantity) if quantity.positive?
    end
    return "" if lines.empty? && @missing_only

    lines.join("\n") + "\n"
  end

  private

  # Only a physical deck nets: a TCG Live deck's owned_copies is 0 by validation, so proxies would
  # give the same answer, but the rule is stated here rather than left to that validation.
  def wanted(dc)
    @missing_only && @deck.physical? ? dc.proxies : dc.quantity
  end

  # Deliberately not the "(V.n) (Expansion)" grammar AddDeckList documents: pasted for real,
  # it refused Trainer lines this form matches and recognised only some expansion
  # spellings (#112).
  def card_line(dc, quantity)
    prefix = quantity > 1 ? "#{quantity}x " : ""
    "#{prefix}#{card_name(dc.card)}".squish
  end

  def card_name(card)
    case card.card_type
    when "Pokémon" then pokemon_name(card)
    when "Energy"  then energy_name(card)
    when "Trainer" then trainer_name(card)
    else card.name
    end
  end

  def pokemon_name(card)
    abilities = card.abilities.map(&:name).reject { |n| n == TERA_ABILITY }
    [ card.name, *abilities, *card.attacks.map(&:name) ].compact_blank.join(" ")
  end

  def energy_name(card)
    return "Basic #{card.name}" if card.subtype == "Basic Energy"

    card.name
  end

  def trainer_name(card)
    variant = cardmarket_variant(card)
    variant ? "#{card.name} #{variant}" : card.name
  end

  # Extract the Cardmarket variant tag from the product URL slug.
  # Cardmarket disambiguates reprints with a suffix like "V1" or a character name.
  # Example: ".../Bosss-Orders-V1-PAL172" with name "Boss's Orders" -> "V1"
  def cardmarket_variant(card)
    return nil if card.cardmarket_url.blank?

    slug = File.basename(URI.parse(card.cardmarket_url).path)
    slug = slug.sub(PRINTING_CODE, "")
    name_slug = slugify(card.name)
    return nil unless slug.start_with?(name_slug)

    suffix = slug.delete_prefix(name_slug).delete_prefix("-")
    suffix.presence&.tr("-", " ")
  end

  # A hyphen in the name is a word break on Cardmarket too ("U-Turn-Board-V1-UNM211").
  def slugify(name)
    I18n.transliterate(name).gsub(/[^A-Za-z0-9\s-]/, "").split(/[\s-]+/).compact_blank.join("-")
  end
end
