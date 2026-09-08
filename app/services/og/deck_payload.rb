module Og
  # What a shared deck's banner says: its name, how many cards it holds and what it was built
  # for, over the artwork of the two cards that identify it.
  class DeckPayload < ApplicationService
    def initialize(deck)
      @deck = deck
    end

    def call
      Payload.new(
        kind: "deck",
        key: @deck.key,
        title: @deck.name,
        subtitle: subtitle,
        art_urls: art_urls,
        digest: digest
      ).tap(&:validate!)
    end

    private

    # Read once into an Array rather than through the association three times. Every caller has
    # it preloaded (both branches of DecksController#show do), and `size` on an *unloaded*
    # association is a COUNT — a query for a number the rows themselves answer.
    def deck_cards
      @deck_cards ||= @deck.deck_cards.to_a
    end

    # Copies, not rows, and summed in Ruby: `deck_cards.sum(:quantity)` in SQL would bypass that
    # preload for a number the loaded rows already carry.
    def card_count
      @card_count ||= deck_cards.sum(&:quantity)
    end

    # Deck#format_label already names the Standard pool — "Standard (TWM-POR)" — which is the
    # one format whose name does not identify a card pool. It reads standard_pool and both of
    # its bounds, so a caller wanting this for free preloads all three (Deck.with_standard_pool).
    def subtitle
      "#{card_count} #{"card".pluralize(card_count)} · #{@deck.format_label}"
    end

    def art_urls
      @art_urls ||= art_cards.filter_map { |card| card.image_url.presence }.first(MAX_ARTS)
    end

    # An archetype is a human's answer to "which two cards is this deck", so it wins outright
    # when there is one — including when its cards carry no art, in which case the banner falls
    # back to the site one rather than to a different pair of cards than the page shows.
    def art_cards
      return [ @deck.archetype.primary_card, @deck.archetype.secondary_card ].compact if @deck.archetype

      notable_pokemon
    end

    # Decks::ArchetypeDetector's *suggestion* order, copied from archetype_detector.rb:50-52
    # rather than called: that service's #call also runs its matching query, and this must add
    # none. Agreeing with that line is the requirement — the app already has one notion of "the
    # notable Pokémon" and a banner disagreeing with the archetype form would be a second.
    #
    # The `uniq(&:name)` is half of it: two printings of one Pokémon otherwise rank first and
    # second and the banner draws the same card twice.
    # Decks::ArchetypeDetector's own ranking, called rather than copied: the banner must not rank a
    # deck's Pokémon differently from the archetype that service would suggest for it. It reads the
    # loaded association and issues no query.
    def notable_pokemon = Decks::ArchetypeDetector.notable_pokemon(@deck)

    # DeckCard belongs_to :deck carries no `touch: true` (deck_card.rb:2), so adding,
    # requantifying or removing a card leaves decks.updated_at alone — measured: create, update
    # and destroy all leave it untouched. The deck-cards' count and newest timestamp are
    # therefore terms of their own; without them the decklist would change the banner's content
    # and never its address, which under Cache-Control: immutable is permanent. `touch: true` was
    # the tempting fix and is rejected: it would move updated_at on every allocation write
    # app-wide to serve this one feature. Both terms read the loaded rows, so both are free.
    def digest
      Payload.digest_of([
        LAYOUT_VERSION, "deck", @deck.key, @deck.updated_at.to_i,
        deck_cards.size, deck_cards.map { |deck_card| deck_card.updated_at.to_i }.max, *art_urls
      ])
    end
  end
end
