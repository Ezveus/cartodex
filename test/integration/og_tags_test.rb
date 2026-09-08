require "test_helper"

# What a page advertises to a chat client. The sweep over the whole public surface lives in
# PublicAccessTest; this file is about the choices — whose payload a page hands over, and what it
# falls back to.
class OgTagsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @owner, name: "Raging Bolt ex / Teal Mask Ogerpon ex")
  end

  def og(property)
    css_select("meta[property='#{property}']").first&.[]("content")
  end

  test "a shared deck advertises its own banner, absolute and versioned" do
    @deck.update!(shared: true)

    get deck_path(@deck)

    image = og("og:image")
    assert_match %r{\Ahttps?://}, image, "og:image must be absolute — a crawler has no base URL"
    assert_includes image, "/og/decks/#{@deck.key}"
    assert_match(/[?&]v=[0-9a-f]{16}\b/, image)
    assert_equal @deck.name, og("og:title")
    assert_equal deck_url(@deck.key), og("og:url")
  end

  # The inverse assertion, and the only one in the suite that fails when og_preview branches on
  # `show?` rather than on the policy: for anybody but the owner the two agree.
  test "the owner's own private deck falls back to the site banner" do
    @deck.update!(shared: false)
    sign_in @owner

    get deck_path(@deck)

    assert_response :success
    assert_equal "#{root_url}og-default.jpg", og("og:image")
    assert_equal "Cartodex", og("og:title")
    # No canonical URL on the site payload: "/" would be a false claim about this page.
    assert_nil og("og:url")
  end

  test "an archetype and a card each advertise their own banner" do
    archetype = archetypes(:standings_marker)
    get archetype_path(archetype)
    assert_includes og("og:image"), "/og/archetypes/#{archetype.slug}"
    assert_equal archetype.name, og("og:title")
    assert_equal archetype_url(archetype.slug), og("og:url")

    card = cards(:doublade)
    get card_path(card)
    assert_includes og("og:image"), "/og/cards/#{card.id}"
    assert_equal card.name, og("og:title")
  end

  test "a page with no payload of its own still advertises the site banner" do
    sign_in @owner

    get settings_path

    assert_response :success
    assert_equal "#{root_url}og-default.jpg", og("og:image")
    assert_equal "website", og("og:type")
  end

  # og:* is RDFa and reads `property`; the Twitter card spec reads `name`. A crawler looking for
  # one does not find the other, and emitting both under one attribute is the mistake that looks
  # right in a browser's inspector.
  test "the twitter tags use name and the open graph tags use property" do
    @deck.update!(shared: true)

    get deck_path(@deck)

    assert_select "meta[property='og:image']", 1
    assert_select "meta[name='twitter:image']", 1
    assert_select "meta[name='og:image']", 0
    assert_select "meta[property='twitter:image']", 0
    assert_select "meta[name='twitter:card'][content=?]", "summary_large_image"
  end

  test "the deck banner's dimensions are advertised, because a client sizes the card from them" do
    @deck.update!(shared: true)

    get deck_path(@deck)

    assert_equal "1200", og("og:image:width")
    assert_equal "630", og("og:image:height")
    assert_equal "image/jpeg", og("og:image:type")
  end
end
