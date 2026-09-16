# Write the fragments `bin/scrape_official_cards` captured into `cards`, `attacks` and
# `abilities`.
#
# A stopgap for a set Limitless does not have yet — see
# `docs/superpowers/specs/2026-09-16-official-card-import-design.md`. It deliberately mirrors
# `Cards::Fetcher`'s two governing habits: a printing already in the database is left untouched,
# and the associations are *built* so that one `save!` computes a fingerprint that sees them.
class Cards::OfficialImporter < ApplicationService
  Result = Struct.new(:imported, :skipped, :failed, keyword_init: true)

  # `dir` holds one fragment per card, named `<slug>_<number>.html`. The slug is what separates
  # the two sets this release ships: `30th/1` is Exeggcute and `30th-c/1` is Charizard, and
  # (set_name, set_number) is UNIQUE, so reading both under one code is a collision rather than a
  # bigger import.
  def initialize(dir:, slug:, set_code:, set_full_name: nil)
    @dir = dir
    @slug = slug
    @set_code = set_code
    @set_full_name = set_full_name
  end

  def call
    card_set = find_or_create_set
    imported = 0
    skipped = 0
    failed = []

    fragments.each do |path|
      case import_one(path, card_set)
      in :imported then imported += 1
      in :skipped then skipped += 1
      in [ :failed, message ] then failed << [ path, message ]
      end
    end

    # Two rarities this set introduces — "Futuristic" and "Classic" — are new to the catalogue,
    # and /cards caches the distinct list for an hour. Same reason CardSets::Importer does it.
    Card.forget_filter_values

    Result.new(imported: imported, skipped: skipped, failed: failed)
  end

  private

  def fragments
    Dir[File.join(@dir, "#{@slug}_*.html")].sort
  end

  def find_or_create_set
    card_set = CardSet.find_or_initialize_by(code: @set_code)
    card_set.name ||= @set_full_name.presence || @set_code
    card_set.save!
    card_set
  end

  def import_one(path, card_set)
    parsed = Cards::OfficialParser.call(File.read(path))
    number = parsed[:set_number]
    raise Cards::OfficialParser::ParseError, "no collector number" if number.blank?

    # Presence, not freshness, is the guard — the rule #121 established for Cards::Fetcher. Here
    # it matters twice over: a row this importer did not write is the *richer* one, carrying the
    # regulation mark and the prices this source cannot supply.
    return :skipped if Card.exists?(set_name: @set_code, set_number: number)

    build_card(parsed, number, card_set).save!
    :imported
  rescue Cards::OfficialParser::ParseError, ActiveRecord::RecordInvalid => e
    [ :failed, e.message ]
  end

  def build_card(parsed, number, card_set)
    card = Card.new(
      set_name: @set_code,
      set_number: number,
      card_set: card_set,
      **parsed.slice(
        :name, :card_type, :stage, :subtype, :hp, :type_symbol, :evolves_from,
        :weakness, :resistance, :retreat_cost, :rarity, :set_full_name, :artist,
        :image_url, :effect
      )
    )
    card.pokemon_subtype = PokemonSubtype.for_card_name(card.name) if card.card_type == "Pokémon"

    # Built, never created: `compute_fingerprint` is a `before_save` that reads the card's attacks
    # and abilities, so a card saved before them takes the fingerprint of a card with none — and
    # that fingerprint is what Decks::ArchetypeDetector matches on and Cards::Printings groups by.
    parsed[:attacks].each { card.attacks.build(**_1) }
    parsed[:abilities].each { card.abilities.build(**_1) }
    card
  end
end
