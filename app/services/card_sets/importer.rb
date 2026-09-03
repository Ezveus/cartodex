require "nokogiri"

class CardSets::Importer < ApplicationService
  BASE_URL = "https://limitlesstcg.com"

  # Limitless prints the release date as the first segment of the infobox line
  # under the set heading: "22nd May 2026 • 122 Cards • $641.12 • 578.42€".
  # An unreleased set omits it and the line starts with the card count, which is
  # why this matches an explicit ordinal date instead of handing the whole line
  # to Date.parse — that would read "122 Cards" as a day of the current month.
  RELEASE_DATE = /\b\d{1,2}(?:st|nd|rd|th)\s+[A-Za-z]+\s+\d{4}\b/

  def initialize(url)
    @url = url
    @set_code = url.split("/").last
  end

  def call
    html = HttpFetcher.call(@url)
    doc = Nokogiri::HTML(html)

    card_set = find_or_create_set(doc)
    card_urls = extract_card_urls(doc)

    imported = 0
    card_urls.each do |card_url|
      card = Cards::Fetcher.call(card_url)
      card.update!(card_set: card_set) if card.card_set_id != card_set.id
      imported += 1
    end

    # An import is one of the two things that can put a new rarity or regulation mark in the
    # catalog, and /cards caches those lists.
    Card.forget_filter_values

    { card_set: card_set, imported: imported }
  end

  private

  def find_or_create_set(doc)
    card_set = CardSet.find_or_initialize_by(code: @set_code)
    card_set.name ||= parse_set_name(doc)
    card_set.logo_url ||= parse_logo_url(doc)
    card_set.release_date ||= parse_release_date(doc)
    card_set.save!
    card_set
  end

  def parse_set_name(doc)
    heading = doc.at_css("h1, .set-name")
    return @set_code unless heading

    heading.text.strip.sub(/\s*\(#{@set_code}\)\s*/, "").strip.presence || @set_code
  end

  def parse_logo_url(doc)
    doc.at_css("img[src*='/sets/']")&.attr("src")
  end

  def parse_release_date(doc)
    match = doc.at_css(".infobox .infobox-line")&.text&.match(RELEASE_DATE)
    return if match.nil?

    Date.parse(match[0])
  rescue Date::Error
    nil
  end

  def extract_card_urls(doc)
    doc.css("a[href^='/cards/#{@set_code}/']").filter_map do |link|
      href = link["href"]
      next if href.count("/") < 3 # skip non-card links
      "#{BASE_URL}#{href}"
    end.uniq
  end
end
