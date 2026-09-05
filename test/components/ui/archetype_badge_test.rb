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

  test "wraps the badge in an anchor when given an href" do
    html = Ui::ArchetypeBadge.new(archetype: @archetype, href: "/archetypes/7").call

    assert_match %r{\A<a href="/archetypes/7"><span class="badge}, html
    assert_includes html, @archetype.name
  end

  # The trap this component walks into. Decks::ImportJob broadcasts a Decks::DeckCard — which
  # renders Decks::ClassificationBadges, which renders this — with a bare Phlex `.call`, outside
  # any request. `link_to` and a `_path` helper both resolve through a view_context that does not
  # exist there and raise NoMethodError, so an anchor written by hand is not a style preference:
  # with link_to, every import of a deck the detector tagged failed its broadcast.
  test "renders a linked badge outside a request" do
    deck = Deck.new(id: 1, key: "sample", name: "Sample", format: "standard",
                    archetype: @archetype)

    html = Decks::DeckCard.new(deck: deck, with_actions: false).call

    assert_includes html, %(<a href="/archetypes/#{@archetype.id}">)
  end
end
