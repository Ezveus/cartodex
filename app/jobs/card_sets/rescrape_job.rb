class CardSets::RescrapeJob < ApplicationJob
  queue_as :default

  BASE_URL = "https://limitlesstcg.com".freeze

  def perform(card_set_id)
    card_set = CardSet.find(card_set_id)
    card_set.cards.find_each do |card|
      url = "#{BASE_URL}/cards/#{card.set_name}/#{card.set_number}"
      ::Cards::Fetcher.call(url, force: true)
    rescue => e
      Rails.logger.warn "Rescrape failed for #{card.set_name}/#{card.set_number}: #{e.message}"
    end
  end
end
