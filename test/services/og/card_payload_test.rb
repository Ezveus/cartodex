require "test_helper"

class Og::CardPayloadTest < ActiveSupport::TestCase
  ART = "https://cards.test/ogerpon.png".freeze

  setup do
    @card = cards(:teal_mask_ogerpon_ex)
  end

  # update_column, not update!: Card's before_save recomputes the fingerprint the fixtures spell
  # out by hand, and leaving updated_at alone is what lets the digest tests name a single cause.
  def give_art(card, url)
    card.update_column(:image_url, url)
  end

  test "the card payload names the printing and draws the card" do
    give_art(@card, ART)

    payload = Og::CardPayload.call(@card.reload)

    assert_equal "card", payload.kind
    assert_equal @card.id.to_s, payload.key
    assert_equal "Teal Mask Ogerpon ex", payload.title
    assert_equal "TWM · 25", payload.subtitle
    assert_equal [ ART ], payload.art_urls
    assert_match(/\A[0-9a-f]{16}\z/, payload.digest)
  end

  # A card is addressed by its integer id, but a key is a URL segment and a cache path segment
  # either way — the endpoint and Og::Cache both interpolate it, so it is a String here for the
  # reason `kind` is.
  test "the key is a String" do
    assert_kind_of String, Og::CardPayload.call(@card).key
  end

  test "a card with no artwork yields no art urls" do
    payload = Og::CardPayload.call(@card)

    assert_equal [], payload.art_urls
    assert_match(/\A[0-9a-f]{16}\z/, payload.digest)
  end

  test "the digest moves when the card is touched" do
    before = Og::CardPayload.call(@card).digest

    # updated_at is second-resolution, so the clock is moved rather than trusted.
    travel 1.hour do
      @card.touch
    end

    assert_not_equal before, Og::CardPayload.call(@card.reload).digest
  end

  test "the digest moves when the artwork changes" do
    give_art(@card, ART)
    before = Og::CardPayload.call(@card.reload).digest

    give_art(@card, "https://cards.test/ogerpon-alternate.png")

    assert_not_equal before, Og::CardPayload.call(@card.reload).digest
  end

  # Everything the card banner says is a column of `cards`, so CardsController#show — which
  # preloads :pokemon_subtype and nothing else — pays nothing for it.
  test "costs no query" do
    card = Card.find(@card.id)

    assert_queries_count(0) do
      Og::CardPayload.call(card)
    end
  end
end
