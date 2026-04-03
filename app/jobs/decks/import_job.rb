class Decks::ImportJob < ApplicationJob
  def perform(decklist, user, deck_name, import_id)
    deck = Decks::Fetcher.call(decklist, user, deck_name)
    deck_count = user.decks.count

    Turbo::StreamsChannel.broadcast_remove_to(
      user, :notifications,
      target: "importing-#{import_id}"
    )

    Turbo::StreamsChannel.broadcast_append_to(
      user, :notifications,
      target: "flash-messages",
      html: <<~HTML
        <div class="flash flash-notice" data-controller="flash">
          Deck "#{ERB::Util.html_escape(deck.name)}" imported successfully (#{deck.deck_cards.count} cards).
        </div>
      HTML
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      user, :notifications,
      target: "deck-count",
      html: %(<span id="deck-count" data-decks-target="count">#{deck_count}</span>)
    )
  rescue => e
    Turbo::StreamsChannel.broadcast_remove_to(
      user, :notifications,
      target: "importing-#{import_id}"
    )

    Turbo::StreamsChannel.broadcast_append_to(
      user, :notifications,
      target: "flash-messages",
      html: <<~HTML
        <div class="flash flash-alert" data-controller="flash">
          Import of deck "#{ERB::Util.html_escape(deck_name)}" failed: #{ERB::Util.html_escape(e.message)}
        </div>
      HTML
    )
  end
end
