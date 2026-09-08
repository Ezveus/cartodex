module Og
  # What an archetype's banner says: its name, over its two member cards.
  #
  # It reads `primary_card` and `secondary_card` and **nothing else**, deliberately.
  # ArchetypesController#show already preloads exactly that pair, and its cost is pinned by a
  # literal `assert_equal 17` in three places — so any other association read here is a query
  # this page has no budget for.
  class ArchetypePayload < ApplicationService
    def initialize(archetype)
      @archetype = archetype
    end

    # No subtitle. The archetype page prints "N lists" four times over, but that number depends
    # on which Standard pool and which venue the reader has selected, so a number baked into a
    # shareable image would be a number from a context the image cannot show — the same trap
    # docs/architecture/archetype-metagame.md describes for the pool option's own label.
    def call
      Payload.new(
        kind: "archetype",
        key: @archetype.slug,
        title: @archetype.name,
        subtitle: nil,
        art_urls: art_urls,
        digest: digest
      ).tap(&:validate!)
    end

    private

    def art_urls
      @art_urls ||= art_cards.filter_map { |card| card.image_url.presence }.first(MAX_ARTS)
    end

    # compact because a secondary is optional — a single-member archetype draws one card.
    def art_cards
      [ @archetype.primary_card, @archetype.secondary_card ].compact
    end

    # The chosen arts are a term of their own because the archetype's own updated_at does not
    # move when a card's image_url does: only a `force: true` rescrape rewrites one.
    def digest
      Payload.digest_of([
        LAYOUT_VERSION, "archetype", @archetype.slug, @archetype.updated_at.to_i, *art_urls
      ])
    end
  end
end
