require "nokogiri"

# Read one card out of a `section.card-detail` fragment captured from the official Pokémon card
# database, and answer the attributes `Cards::OfficialImporter` writes.
#
# This exists because Limitless has no 30th Celebration and `Cards::Fetcher` reads Limitless and
# nothing else — see `docs/superpowers/specs/2026-09-16-official-card-import-design.md`. It is a
# stopgap: once Limitless publishes under the same set code, the admin panel's existing Rescrape
# rewrites every one of these rows from `Cards::Fetcher` and this service stops mattering.
#
# It writes what `Cards::Fetcher` writes, in the shapes `Cards::Fetcher` writes them, because these
# rows land in one table beside 4732 others and every reader is shared.
class Cards::OfficialParser < ApplicationService
  class ParseError < StandardError; end

  # The icon class is the canonical name, not the `title` attribute: the class is what the page's
  # own stylesheet keys on, and the weakness, resistance and attack-cost icons carry no `title` at
  # all — only the type icon does. Reading the tooltip therefore loses three fields out of four.
  #
  # **Derived, never typed out.** Every one of `Card::ENERGY_TYPES` downcases to exactly the slug
  # the page uses, so the mapping is a fact about the model rather than a second list beside it.
  # A hand-written table here passed every test in this file with Fairy and Psychic swapped —
  # both are valid members, so `Card`'s inclusion validation cannot see the swap, no fixture in
  # this set plays either type, and the wrong letter would have gone into `attacks.cost` and from
  # there into the fingerprint.
  ENERGY_BY_SLUG = Card::ENERGY_TYPES.index_by(&:downcase).freeze

  # An attack costing nothing renders as one `li` carrying this and no `data-energy-type`.
  FREE_SLUG = "free".freeze

  # Limitless writes a zero-cost attack as "0" — 26 attacks in the catalogue carry it and none
  # carries an empty string. `cost` feeds `Card#compute_fingerprint`, so the difference is the
  # difference between a card that groups with its other printings and one that never does.
  FREE_COST = "0".freeze

  # `attacks.cost` holds Limitless's one-letter alphabet ("WW", "LLC"), so the energy names the
  # page prints have to be folded back onto it. Derived rather than retyped: a hand-written second
  # copy could swap two valid members and store a valid, wrong, fingerprint-bearing letter.
  SYMBOL_BY_TYPE = Cards::Fetcher::ENERGY_SYMBOLS.invert.freeze

  def initialize(html)
    @html = html
  end

  def call
    doc = Nokogiri::HTML(@html)
    @root = doc.at_css(".card-detail") || doc
    @description = @root.at_css(".card-description")
    # Imperva answers a refused request with HTTP 200 and a ~930-byte block page. The scraper has
    # no tests, so this raise is what stands between that page and a row in `cards`.
    raise ParseError, "no card detail in this fragment" unless @description

    attributes
  end

  private

  def attributes
    {
      name: text(@description.at_css("h1")),
      card_type: card_type,
      stage: stage,
      subtype: subtype,
      hp: hp,
      type_symbol: type_symbol,
      evolves_from: text(@description.at_css(".card-type h4 a")),
      weakness: stat_energy("Weakness"),
      resistance: stat_energy("Resistance"),
      retreat_cost: retreat_cost,
      rarity: rarity,
      set_number: set_number,
      source_id: @root.at_css("[data-card-id]")&.attr("data-card-id"),
      set_full_name: text(@root.at_css(".stats-footer h3")),
      artist: text(@root.at_css(".illustrator a")),
      image_url: @root.at_css(".card-image img")&.attr("src"),
      effect: effect,
      attacks: attacks,
      abilities: abilities
    }
  end

  def type_line
    @type_line ||= text(@description.at_css(".card-type h2")).to_s
  end

  def card_type
    # `\ATrainer` is tested FIRST, and the order is the whole rule: a Pokémon Tool's type line
    # reads "Trainer-Pokémon Tool", so a `/Pokémon/` test that ran first claimed it — and the card
    # then went on to be given stage "Basic" and retreat 0 before the model refused it with an
    # error about missing HP. `Cards::Fetcher` has the opposite order and is safe only because
    # Limitless writes "Trainer - Tool" without the word.
    case type_line
    when /\ATrainer/ then "Trainer"
    when /Pokémon/ then "Pokémon"
    when /Energy/ then "Energy"
    else raise ParseError, "unknown card type: #{type_line.inspect}"
    end
  end

  # The type line prints a stage for an ordinary Pokémon and the rule box *instead of* one for an
  # `ex` — so on those the stage has to be inferred, and only the Basic case can be. That matters
  # well beyond this column: `Decks::Odds::Groups` counts a Basic as
  # `card_type == "Pokémon" && stage == "Basic"` to derive the mulligan rate, so a Basic left
  # nil makes the page wrong in the reassuring direction. Stage 1 and Stage 2 are not
  # distinguishable here and are left nil rather than guessed — 748 cards already carry nil.
  def stage
    return nil unless card_type == "Pokémon"

    case type_line
    when /Basic/ then "Basic"
    when /Stage 2/ then "Stage 2"
    when /Stage 1/ then "Stage 1"
    else @description.at_css(".card-type h4 a") ? nil : "Basic"
    end
  end

  # "Trainer-Item" -> "Item". Read generically rather than against a vocabulary list: the 17
  # captured pages hold only Item, so a list would be a guess about Supporter, Stadium, Tool and
  # Energy, while whatever follows the dash is what Limitless stores anyway.
  def subtype
    return nil if card_type == "Pokémon"

    value = type_line.split("-", 2).last&.strip.presence
    return value unless card_type == "Energy" && value

    # The catalogue's energy vocabulary is "Basic Energy" (50 rows) and "Special Energy" (31),
    # written by Limitless, and four readers test those exact strings — `Card` exempts only
    # "Basic Energy" from the rarity-presence validation, and the JSON, Cardmarket and PDF
    # exporters each compare against it. No captured page is an Energy card, so the official
    # spelling is unknown; appending the word when it is missing answers both possibilities.
    value.end_with?("Energy") ? value : "#{value} Energy"
  end

  def hp
    text(@description.at_css(".card-hp"))&.slice(/\d+/)&.to_i
  end

  def type_symbol
    energy_name(@description.at_css(".card-basic-info .right i.energy"))
  end

  def energy_name(node)
    slug = node&.attr("class").to_s[/icon-([a-z]+)/, 1]
    ENERGY_BY_SLUG[slug]
  end

  def stat(heading)
    @root.css(".pokemon-stats .stat").find { |s| text(s.at_css("h4")) == heading }
  end

  def stat_energy(heading)
    energy_name(stat(heading)&.at_css("i.energy"))
  end

  # A Pokémon whose retreat list is empty retreats for free, and `Card` validates `retreat_cost`
  # present and `>= 0` on every Pokémon — so 0 and nil are a saved card and a refused one. A
  # Trainer has no retreat block at all and keeps nil, which the same validation permits.
  def retreat_cost
    return nil unless card_type == "Pokémon"

    stat("Retreat Cost")&.css("li")&.size.to_i
  end

  # "21/128 Double Rare" -> "21" and "Double". The first token only, which is the rule
  # `Cards::Fetcher#parse_rarity` applies to Limitless — the catalogue holds "Double", not
  # "Double Rare". Nothing is translated: the official vocabulary says "Illustration Rare" where
  # Limitless says "Art Rare", and this set adds two names Limitless has never given, so a
  # mapping table would have to invent them. See the spec.
  def footer
    @footer ||= text(@root.at_css(".stats-footer span")).to_s
  end

  def set_number
    footer[%r{\A(\S+)/}, 1]
  end

  def rarity
    footer[%r{\A\S+/\S+\s+(\S+)}, 1]
  end

  # A Pokémon's printed text lives on its attacks, and Limitless leaves `cards.effect` nil for
  # them. The guard is load-bearing rather than defensive: an attack's effect sits in a `<pre>`
  # inside `.ability`, which is the very selector a Trainer's text uses, so without it every
  # Pokémon in the set would carry its first attack's text in this column.
  def effect
    return nil if card_type == "Pokémon"

    paragraphs(@root.at_css(".pokemon-abilities .ability pre"))
  end

  # `.text` on the container runs the paragraphs together — Ultra Ball's two sentences arrive as
  # one — so they are joined explicitly, and the empty `<p>` the page uses as a spacer is dropped.
  def paragraphs(node)
    return nil unless node

    node.css("p").map { text(_1) }.compact_blank.join("\n\n").presence ||
      text(node).presence
  end

  # Attacks, abilities and the "Pokémon ex rule" box all render as `.ability`, and each of the
  # three is told apart by what it carries rather than by its position: an ability has the
  # `.poke-ability` label, an attack has both an energy list and a name, and the rule box has a
  # name and no energy list. Storing the rule box as an ability would put the same sentence on
  # all 24 ex cards in the set and move every one of their fingerprints.
  def ability_blocks
    @ability_blocks ||= @root.css(".pokemon-abilities .ability")
  end

  def attacks
    ability_blocks
      .reject { _1.at_css(".poke-ability") }
      .select { _1.at_css("ul.left") && _1.at_css("h4.label") }
      .each_with_index.map do |block, index|
        {
          name: text(block.at_css("h4.label")),
          cost: attack_cost(block),
          damage: text(block.at_css("span.right")).presence,
          effect: paragraphs(block.at_css("pre")),
          position: index
        }
      end
  end

  def attack_cost(block)
    types = block.css("ul.left [data-energy-type]").map { _1.attr("data-energy-type") }
    if types.empty?
      # An attack with no typed energy must be the free icon, and saying so is what stops an
      # icon class nobody has mapped from silently becoming a zero-cost attack.
      return FREE_COST if block.at_css("ul.left i.energy.icon-#{FREE_SLUG}")

      raise ParseError, "attack #{text(block.at_css('h4.label')).inspect} has an unreadable cost"
    end

    types.map do |type|
      SYMBOL_BY_TYPE.fetch(type) { raise ParseError, "unknown energy: #{type.inspect}" }
    end.join
  end

  def abilities
    ability_blocks.select { _1.at_css(".poke-ability") }.each_with_index.map do |block, index|
      {
        name: ability_name(block),
        effect: paragraphs(block),
        position: index
      }
    end
  end

  # The source writes U+2019 where this catalogue is written with U+0027, throughout: measured,
  # 421 card names carry the plain apostrophe and none carries the typographic one, and 1626
  # attack effects say "opponent's" against 9 that do not. Leaving it costs more than tidiness —
  # CardLabels::RoleSuggester's gust and disruption rules spell it plainly, so these cards would
  # silently fall out of the role vocabulary, and a Trainer's fingerprint is SHA256 of its name
  # alone, so one apostrophe would make a reprint its own island, unreachable from
  # Cards::Printings and from any search typed on an ordinary keyboard.
  #
  # Only that one character. It is the sole codepoint above U+2000 in all 17 captured fragments,
  # and `×` (U+00D7) is deliberately left alone — 395 attacks in the catalogue already spell
  # their damage with it.
  # "[Pokémon Power] Energy Burn" -> "Energy Burn". The page prints the card's era in front of an
  # old rule box; no ability in the catalogue carries a bracket, because Limitless writes
  # "Ability: Energy Burn" and Cards::Fetcher strips that prefix. Same normalisation, other
  # source. It is not cosmetic: ability names feed compute_fingerprint, and
  # Decks::CardmarketExporter joins them into the wishlist line it sends to Cardmarket.
  def ability_name(block)
    name = text(block.css("h3 div").reject { _1.matches?(".poke-ability") }.first)
    name&.sub(/\A\[[^\]]*\]\s*/, "").presence
  end

  def text(node)
    node&.text&.squish&.tr("\u2019", "'").presence
  end
end
