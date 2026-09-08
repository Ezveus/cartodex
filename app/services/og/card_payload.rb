module Og
  # What a card's banner says: the card's name, the printing it is, and the card itself.
  #
  # Everything here is a column of `cards`, so CardsController#show — which preloads
  # :pokemon_subtype and nothing else — pays no query for it.
  class CardPayload < ApplicationService
    def initialize(card)
      @card = card
    end

    def call
      Payload.new(
        kind: "card",
        key: @card.id.to_s,
        title: @card.name,
        subtitle: subtitle,
        art_urls: art_urls,
        digest: digest
      ).tap(&:validate!)
    end

    private

    # The printing, the way Card#printing_label says it and every surface that designates one
    # names it: the set and the number are what tell two rows sharing a name apart. Both are
    # validated present, so there is no partial form to fall back to.
    def subtitle
      "#{@card.set_name} · #{@card.set_number}"
    end

    def art_urls
      @art_urls ||= [ @card.image_url.presence ].compact
    end

    def digest
      Payload.digest_of([
        LAYOUT_VERSION, "card", @card.id, @card.updated_at.to_i, *art_urls
      ])
    end
  end
end
