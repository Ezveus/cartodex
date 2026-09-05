require "test_helper"

# The badge is rendered on three surfaces with three different answers to "may this reader
# follow a link to /archetypes?", so `href:` is a caller's decision and its absence has to stay
# exactly what it always was.
class Ui::ArchetypeBadgeTest < ActiveSupport::TestCase
  setup do
    @archetype = archetypes(:ogerpon)
  end

  test "renders no anchor at all without an href" do
    html = Ui::ArchetypeBadge.new(archetype: @archetype).call

    assert_no_match(/<a\b/, html)
    assert_includes html, @archetype.name
  end

  # The breakout is part of the anchor, not of its callers: every surface that passes an href
  # renders this row inside a Turbo Frame, and frame-scoped the click swaps that frame for Turbo's
  # missing-frame error instead of navigating.
  test "wraps the badge in an anchor that leaves its Turbo Frame when given an href" do
    html = Ui::ArchetypeBadge.new(archetype: @archetype, href: "/archetypes/7").call

    assert_match %r{\A<a href="/archetypes/7" data-turbo-frame="_top"><span class="badge}, html
    assert_includes html, @archetype.name
  end

  # The trap this component walks into. Decks::ImportJob broadcasts a Decks::DeckCard — which
  # renders Decks::ClassificationBadges, which renders this — with a bare Phlex `.call`, outside
  # any request. `link_to` and a `_path` helper both resolve through a view_context that does not
  # exist there and raise NoMethodError, so an anchor written by hand is not a style preference:
  # with link_to, every import of a deck the detector tagged failed its broadcast.
  test "renders a linked badge outside a request" do
    html = Decks::ClassificationBadges.new(deck: sample_deck, linked: true).call

    assert_includes html, %(<a href="/archetypes/#{@archetype.id}" data-turbo-frame="_top">)
  end

  # The other half of the same decision: Decks::DeckCard wraps its whole body in an anchor, so the
  # badge row inside it must not add one. An HTML5 parser closes the outer anchor at the second
  # start tag, which dropped the description and the card count out of the deck's own link — and
  # `assert_select`, parsing HTML4, could not see it.
  test "a deck card renders the badge unlinked, so its own link is not split" do
    html = Decks::DeckCard.new(deck: sample_deck, with_actions: false).call

    assert_includes html, @archetype.name
    assert_no_match %r{<a href="/archetypes/}, html
    # Exactly one anchor in the card: the deck's own.
    assert_equal 1, html.scan(/<a\b/).size
  end

  private

  def sample_deck
    Deck.new(id: 1, key: "sample", name: "Sample", format: "standard", archetype: @archetype)
  end
end
