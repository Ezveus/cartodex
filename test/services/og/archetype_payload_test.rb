require "test_helper"

class Og::ArchetypePayloadTest < ActiveSupport::TestCase
  PRIMARY_ART = "https://cards.test/budew.png".freeze
  SECONDARY_ART = "https://cards.test/ogerpon.png".freeze

  setup do
    @archetype = archetypes(:budew_ogerpon)
  end

  # Every fixture card carries image_url: nil (cards.yml sets none), so every test about artwork
  # has to write one. update_column and not update!: Card's before_save recomputes the
  # fingerprint the fixtures spell out by hand, and leaving updated_at alone is what lets the
  # digest tests below name a single cause.
  def give_art(card, url)
    card.update_column(:image_url, url)
  end

  # The subtitle is nil on purpose: the archetype page prints "N lists" four times over, but that
  # number depends on which Standard pool the reader has selected, and a number baked into a
  # shareable image would come from a context the image cannot show.
  test "the archetype payload is its name over its two member cards" do
    give_art(cards(:budew_pre), PRIMARY_ART)
    give_art(cards(:teal_mask_ogerpon_ex), SECONDARY_ART)

    payload = Og::ArchetypePayload.call(@archetype.reload)

    assert_equal "archetype", payload.kind
    assert_equal @archetype.slug, payload.key
    assert_equal "Budew / Teal Mask Ogerpon ex", payload.title
    assert_nil payload.subtitle
    assert_equal [ PRIMARY_ART, SECONDARY_ART ], payload.art_urls
    assert_match(/\A[0-9a-f]{16}\z/, payload.digest)
  end

  test "an archetype with no secondary draws one card" do
    give_art(cards(:teal_mask_ogerpon_ex), SECONDARY_ART)

    payload = Og::ArchetypePayload.call(archetypes(:ogerpon).reload)

    assert_equal [ SECONDARY_ART ], payload.art_urls
  end

  # Zero resolvable arts is a normal state, not an error: Og::Renderer falls back to the static
  # Cartodex banner. The payload still validates, so the page still emits a preview.
  test "member cards with no artwork yield no art urls" do
    payload = Og::ArchetypePayload.call(@archetype)

    assert_equal [], payload.art_urls
    assert_match(/\A[0-9a-f]{16}\z/, payload.digest)
  end

  test "the digest moves when the archetype itself is touched" do
    before = Og::ArchetypePayload.call(@archetype).digest

    # updated_at is second-resolution, so the clock is moved rather than trusted.
    travel 1.hour do
      @archetype.touch
    end

    assert_not_equal before, Og::ArchetypePayload.call(@archetype.reload).digest
  end

  # The subject's own updated_at does not move when a card's art does — only a `force: true`
  # rescrape rewrites an image_url — so the chosen arts are a term of the digest in their own
  # right. This is the assertion that says so: nothing else about the archetype changes here.
  test "the digest moves when a member card's artwork changes" do
    give_art(cards(:budew_pre), PRIMARY_ART)
    before = Og::ArchetypePayload.call(@archetype.reload).digest

    give_art(cards(:budew_pre), "https://cards.test/budew-alternate.png")

    assert_not_equal before, Og::ArchetypePayload.call(@archetype.reload).digest
  end

  # ArchetypesController#show is pinned to a literal `assert_equal 17` in three places, and
  # :primary_card / :secondary_card are already preloaded there. This builder therefore has a
  # budget of zero queries, which means it may read those two associations and nothing else.
  test "costs no query when the two member cards are preloaded" do
    archetype = Archetype.includes(:primary_card, :secondary_card).find(@archetype.id)

    assert_queries_count(0) do
      Og::ArchetypePayload.call(archetype)
    end
  end
end
