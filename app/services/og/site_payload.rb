module Og
  # The banner every page that is not a deck, an archetype or a card gets — and the one a
  # subject degrades to: a private deck, or a subject whose artwork resolved to nothing. It is
  # the committed public/og-default.jpg rather than a render, so there is no subject to key on
  # and nothing for a cache-buster to bust: no key, and no digest.
  class SitePayload < ApplicationService
    TITLE = "Cartodex".freeze
    SUBTITLE = "Pokémon TCG collection, decks and tournament results".freeze

    def call
      Payload.new(
        kind: "site",
        key: nil,
        title: TITLE,
        subtitle: SUBTITLE,
        art_urls: [],
        digest: nil
      ).tap(&:validate!)
    end
  end
end
