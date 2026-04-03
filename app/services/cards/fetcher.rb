require "nokogiri"

# Fetch card text on Limitless and create or update the associated `Card`
class Cards::Fetcher < ApplicationService
  class ParseError < StandardError; end

  ENERGY_SYMBOLS = {
    "G" => "Grass", "R" => "Fire", "W" => "Water", "L" => "Lightning",
    "F" => "Fighting", "P" => "Psychic", "D" => "Darkness", "M" => "Metal",
    "Y" => "Fairy", "N" => "Dragon", "C" => "Colorless"
  }.freeze

  def initialize(url)
    @url = url
    @set_name, @set_number = parse_url
  end

  def call
    html = HttpFetcher.call(@url)
    doc = Nokogiri::HTML(html)

    card = Card.find_or_initialize_by(set_name: @set_name, set_number: @set_number)
    assign_attributes(card, doc)
    assign_attacks(card, doc)
    card.save!
    card
  end

  private

  # Parse urls like https://limitlesstcg.com/cards/{set_name}/{set_number}
  def parse_url
    path = URI.parse(@url).path
    segments = path.split("/")
    # Expected: ["", "cards", "POR", "56"]
    raise ParseError, "Invalid Limitless card URL: #{@url}" unless segments.length >= 4 && segments[1] == "cards"

    [ segments[2], segments[3] ]
  end

  def assign_attributes(card, doc)
    card_text = doc.at_css(".card-text")
    raise ParseError, "Card text section not found" unless card_text

    title = card_text.at_css(".card-text-title")
    type_line = card_text.at_css(".card-text-type")

    card.name = title.at_css(".card-text-name").text.strip
    card.card_type = parse_card_type(type_line)
    card.hp = parse_hp(title)
    card.type_symbol = parse_type_symbol(title)
    card.stage = parse_stage(type_line)
    card.evolves_from = parse_evolves_from(type_line)
    card.image_url = parse_image_url(doc)
    card.rarity = parse_rarity(doc)
    card.set_full_name = parse_set_full_name(doc)
    card.regulation_mark = parse_regulation_mark(doc)
    card.price_usd = parse_price(doc, "usd")
    card.price_eur = parse_price(doc, "eur")

    wrr = card_text.at_css(".card-text-wrr")
    if wrr
      card.weakness = parse_wrr_field(wrr, "Weakness")
      card.resistance = parse_wrr_field(wrr, "Resistance")
      card.retreat_cost = parse_retreat_cost(wrr)
    end
  end

  def assign_attacks(card, doc)
    card.attacks.destroy_all if card.persisted?

    doc.css(".card-text-attack").each_with_index do |attack_el, index|
      info = attack_el.at_css(".card-text-attack-info")
      effect_el = attack_el.at_css(".card-text-attack-effect")

      cost_and_name_damage = info.text.strip
      cost = info.at_css(".ptcg-symbol")&.text&.strip || ""
      name_damage = cost_and_name_damage.sub(cost, "").strip

      # Separate attack name from damage: "Cut 10", "Weaponized Swords 60×"
      name, damage = split_attack_name_damage(name_damage)

      card.attacks.build(
        name: name,
        cost: cost,
        damage: damage,
        effect: effect_el&.text&.strip.presence,
        position: index
      )
    end
  end

  def split_attack_name_damage(text)
    if text =~ /\A(.+?)\s+(\d+[×+]?)\z/
      [ $1.strip, $2.strip ]
    else
      [ text.strip, nil ]
    end
  end

  def parse_card_type(type_line)
    text = type_line.text.strip
    if text.include?("Pokémon")
      "Pokémon"
    elsif text.include?("Trainer") || text.include?("Supporter") || text.include?("Item") || text.include?("Stadium") || text.include?("Tool")
      "Trainer"
    elsif text.include?("Energy")
      "Energy"
    else
      raise ParseError, "Unknown card type: #{text}"
    end
  end

  def parse_hp(title)
    title.text[/(\d+)\s*HP/, 1]&.to_i
  end

  def parse_type_symbol(title)
    text = title.text
    ENERGY_SYMBOLS.each_value do |type|
      return type if text.include?("- #{type}")
    end
    nil
  end

  def parse_stage(type_line)
    text = type_line.text.strip
    case text
    when /Basic/ then "Basic"
    when /Stage 2/ then "Stage 2"
    when /Stage 1/ then "Stage 1"
    when /VSTAR|VMAX|V-UNION|ex|EX/ then text[/(VSTAR|VMAX|V-UNION|ex|EX)/]
    end
  end

  def parse_evolves_from(type_line)
    link = type_line.at_css("a")
    return nil unless type_line.text.include?("Evolves from") && link

    link.text.strip
  end

  def parse_image_url(doc)
    doc.at_css(".card-image img")&.attr("src")
  end

  def parse_rarity(doc)
    prints_current = doc.at_css(".card-prints-current")
    return nil unless prints_current

    # "  #56 · Common  " or "#57 · Common"
    prints_current.text[/·\s*(\S+)/, 1]
  end

  def parse_set_full_name(doc)
    prints_current = doc.at_css(".card-prints-current .prints-current-details .text-lg")
    return nil unless prints_current

    # "Perfect Order (POR)" -> "Perfect Order"
    prints_current.text.strip.sub(/\s*\(.*\)\s*$/, "")
  end

  def parse_regulation_mark(doc)
    el = doc.at_css(".regulation-mark")
    return nil unless el

    el.text.strip[/\A(\S+)\s+Regulation Mark/, 1]
  end

  def parse_price(doc, currency)
    # Take the first price link for the current print (the one with class="current")
    row = doc.at_css("tr.current")
    return nil unless row

    price_el = row.at_css(".card-price.#{currency}")
    return nil unless price_el

    price_el.text.strip.gsub(/[$€]/, "").to_d
  end

  def parse_wrr_field(wrr, field)
    wrr.text[/#{field}:\s*(\S+)/, 1]
  end

  def parse_retreat_cost(wrr)
    wrr.text[/Retreat:\s*(\d+)/, 1]&.to_i
  end
end
