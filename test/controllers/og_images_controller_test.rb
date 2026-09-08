require "test_helper"
require "tmpdir"

# The preview-image endpoint. Every case here stubs Og::Cache.fetch and hands back a file on disk,
# which is the right boundary twice over: it keeps the controller's own behaviour (policy, 404
# shape, cache headers, the deliberately-unread `?v=`) separable from compositing, and it keeps
# this file from needing libvips. Og::RendererTest covers the pixels; the one test below that goes
# through the real cache is marked as such.
class OgImagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @owner)
    @archetype = archetypes(:standings_marker)
    @card = cards(:doublade)

    @dir = Dir.mktmpdir
    # Not a real JPEG and it does not need to be — send_data streams bytes and asserts nothing
    # about them. The SOI marker is here so a failure that dumps the body is recognisable.
    @bytes = "\xFF\xD8\xFF\xDB".b + ("og" * 64).b
    @original_fetch = Og::Cache.method(:fetch)
    @previous_root = Og::Cache.root
    bytes = @bytes
    @fetch_calls = []
    calls = @fetch_calls
    Og::Cache.define_singleton_method(:fetch) do |payload|
      calls << payload
      bytes
    end
  end

  teardown do
    Og::Cache.singleton_class.remove_method(:fetch)
    Og::Cache.define_singleton_method(:fetch, @original_fetch)
    # Restored, unlike the first version of this file: the end-to-end test below sets it, and
    # leaving it pointing into a removed tmpdir hands every later test in this forked worker a
    # broken cache root — the hazard test_helper's parallelize_setup exists for.
    Og::Cache.root = @previous_root
    FileUtils.remove_entry(@dir)
  end

  test "a shared deck's banner answers a visitor with a JPEG" do
    @deck.update!(shared: true)

    get deck_og_image_path(@deck.key)

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_predicate response.body, :present?
    assert_equal "deck", @fetch_calls.sole.kind
  end

  test "an unshared deck's banner is a 404, not a redirect" do
    @deck.update!(shared: false)

    get deck_og_image_path(@deck.key)

    # 404 and not the sign-in redirect DecksController#not_found serves: that override is right
    # for a page a human typed and wrong for an image a crawler asked for, so this controller must
    # not have copied it.
    assert_response :not_found
    assert_empty @fetch_calls
  end

  # The assertion that discriminates DeckPolicy#og_image? from `show?`. Every other case here asks
  # as a stranger, and for a stranger the two answer identically — so with this test removed,
  # `og_image? = show?` is green across the whole file.
  test "the owner is refused their own private deck's banner" do
    @deck.update!(shared: false)
    sign_in @owner

    get deck_og_image_path(@deck.key)

    assert_response :not_found
  end

  test "an unknown deck key is a 404" do
    get deck_og_image_path("no-such-deck-key")

    assert_response :not_found
  end

  test "an archetype and a card answer without a session" do
    get archetype_og_image_path(@archetype.slug)
    assert_response :success
    assert_equal "image/jpeg", response.media_type

    get card_og_image_path(@card.id)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
  end

  # The assertion that holds the lookup order, and nothing else in the suite can: a refused deck
  # and an unknown key answer identically, so what leaked was never the response — it was the work
  # done before the refusal. Spelled with the payload's `includes` on the lookup, an existing
  # private deck paid every preload and an unknown key paid one query, which is an existence oracle
  # by timing and by cost (measured at 1 query / 3.2 ms against 3 / 8.6 ms for a 60-card deck).
  #
  # Query count rather than wall time, because the query count is deterministic and the timing is
  # what the query count causes.
  test "a refused deck costs exactly what an unknown key costs" do
    @deck.update!(shared: false)
    3.times { @deck.deck_cards.create!(card: cards(:doublade), quantity: 1) rescue nil }

    get deck_og_image_path("warming-the-session")

    unknown = count_queries { get deck_og_image_path("no-such-deck-key") }
    refused = count_queries { get deck_og_image_path(@deck.key) }

    assert_response :not_found
    assert_equal unknown, refused,
                 "a private deck must not be distinguishable from an unknown one by cost"
  end

  test "the response is cacheable forever and marked immutable" do
    @deck.update!(shared: true)

    get deck_og_image_path(@deck.key)

    # The literal token, not a max-age regex. `expires_in 1.year, public: true` without
    # `immutable: true` emits only "max-age=…, public", which would pass a /max-age/ assertion
    # while still telling a client to revalidate a URL whose bytes can never change.
    assert_includes response.headers["Cache-Control"], "immutable"
    assert_includes response.headers["Cache-Control"], "public"
    # 1.year is 31_556_952 seconds in ActiveSupport — 365.2425 days, not 365 — so the obvious
    # literal 31536000 is wrong. Derived from the constant rather than spelled out, so the
    # assertion cannot disagree with the controller about what a year is.
    assert_includes response.headers["Cache-Control"], "max-age=#{1.year.to_i}"
  end

  # `?v=` is a cache-buster, never a lookup key. Built from a fabricated digest on purpose: deriving
  # a real prior digest cannot fail, because `updated_at.to_i` is second-resolution and a
  # same-second mutation yields the identical digest — so a test written that way passes even when
  # `v` *is* the key.
  test "a stale v answers the current banner rather than a 404" do
    @deck.update!(shared: true)

    get deck_og_image_path(@deck.key, v: "deadbeefdeadbeef")

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal @deck.key, @fetch_calls.sole.key
    assert_not_equal "deadbeefdeadbeef", @fetch_calls.sole.digest
  end

  test "the payload the endpoint renders is the one the page advertises" do
    @deck.update!(shared: true)

    get deck_path(@deck)
    assert_response :success
    advertised = css_select("meta[property='og:image']").first["content"]

    get advertised
    assert_response :success
    # The page's ?v= and the endpoint's own digest must agree, or a client would forever hold a
    # URL the app never generates again.
    assert_equal @fetch_calls.sole.digest, Rack::Utils.parse_query(URI.parse(advertised).query)["v"]
  end

  # The one case that runs the real cache and the real renderer, so that the endpoint is proven to
  # be wired to them at all and not only to a stub. Requires libvips.
  test "end to end, the real cache produces a real JPEG" do
    Og::Cache.singleton_class.remove_method(:fetch)
    Og::Cache.define_singleton_method(:fetch, @original_fetch)
    Og::Cache.root = Pathname.new(@dir).join("cache")
    @deck.update!(shared: true)

    get deck_og_image_path(@deck.key)

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal [ 1200, 630 ], [ image.width, image.height ]
  end
end
