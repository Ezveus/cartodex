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
    # A run that matched nothing is a typo in the slug, not a finished import — and without this
    # it reported success, exited 0, and created the card_sets row anyway, which is
    # indistinguishable from a complete import of a set whose cards are all already held.
    raise ArgumentError, "no #{@slug}_*.html fragments in #{@dir}" if fragments.empty?

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

  # The name falls back to what the *pages* print rather than to the code, because the argument
  # and the fragments are two independent sources for one fact and nothing else reconciles them:
  # importing the Classic Collection while passing the parent set's name would leave the /cards
  # sidebar saying "30th Celebration" over cards that each say "30th Classic Collection".
  # `||=` so an existing row is never reasserted — the CardSets::Importer rule, which is what
  # keeps a db:seed on every boot from reverting an admin's correction.
  def find_or_create_set
    card_set = CardSet.find_or_initialize_by(code: @set_code)
    card_set.name ||= @set_full_name.presence || printed_set_name || @set_code
    card_set.save!
    card_set
  end

  # Read off the first fragment that parses. Costs one extra parse of one file on a run of 184.
  def printed_set_name
    fragments.each do |path|
      name = Cards::OfficialParser.call(File.read(path))[:set_full_name]
      return name if name.present?
    rescue Cards::OfficialParser::ParseError
      next
    end
    nil
  end

  def import_one(path, card_set)
    parsed = Cards::OfficialParser.call(File.read(path))
    number = parsed[:set_number]
    raise Cards::OfficialParser::ParseError, "no collector number" if number.blank?

    # The page states which set it belongs to, and the filename is only what the scraper called
    # it. A fragment from the other set dropped into this directory would otherwise be filed
    # under this code without a word — and `30th/1` and `30th-c/1` are different cards.
    source_slug = parsed[:source_id].to_s.split("/").first
    if source_slug.present? && source_slug != @slug
      raise Cards::OfficialParser::ParseError, "belongs to #{source_slug}, not #{@slug}"
    end

    # Presence, not freshness, is the guard — the rule #121 established for Cards::Fetcher. Here
    # it matters twice over: a row this importer did not write is the *richer* one, carrying the
    # regulation mark and the prices this source cannot supply.
    return :skipped if Card.exists?(set_name: @set_code, set_number: number)

    build_card(parsed, number, card_set).save!
    :imported
  # RecordNotUnique beside RecordInvalid: the existence check and the write are not one statement,
  # so a competing writer landing the same printing between them is a race the index would
  # otherwise turn into a stack trace that takes the whole run down for one row.
  rescue Cards::OfficialParser::ParseError, ActiveRecord::RecordInvalid,
         ActiveRecord::RecordNotUnique => e
    [ :failed, e.message ]
  end

  def build_card(parsed, number, card_set)
    card = Card.new(
      set_name: @set_code,
      set_number: number,
      card_set: card_set,
      **parsed.except(:source_id).slice(
        :name, :card_type, :stage, :subtype, :hp, :type_symbol, :evolves_from,
        :weakness, :resistance, :retreat_cost, :rarity, :set_full_name, :artist,
        :image_url, :effect
      )
    )
    card.pokemon_subtype = PokemonSubtype.for_card_name(card.name) if card.card_type == "Pokémon"

    # Built, never created, and the caller's `save!` below is the **only** one: `compute_fingerprint`
    # is a `before_save` that reads the card's attacks and abilities, so a card written before them
    # takes the fingerprint of a card with none — and that fingerprint is what
    # Decks::ArchetypeDetector matches on and Cards::Printings groups by.
    #
    # It is the *single* save that carries the rule, not the `build` on its own. Measured: adding
    # an early `card.save!` here while leaving the caller's `save!` in place changes nothing,
    # because Rails re-runs `before_save` on the second write and recomputes the fingerprint from
    # whatever is in memory by then. The bug only appears once something saves early **and** the
    # caller stops re-saving, which is why the test compares against a deliberately attack-less
    # rebuild rather than merely asserting the attacks exist.
    parsed[:attacks].each { card.attacks.build(**_1) }
    parsed[:abilities].each { card.abilities.build(**_1) }
    card
  end
end
