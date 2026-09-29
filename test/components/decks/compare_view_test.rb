require "test_helper"

# The compare table is rendered by two pages now: deck against deck, and a deck version against
# the one before it. The second must link nowhere near the deck page, while the first must render
# exactly as it did before the header became a parameter.
#
# Unpersisted records throughout: the view reads ids, names and `to_param`, nothing else, so no
# row this file relies on can be moved by a fixture another test edits.
class Decks::CompareViewTest < ActiveSupport::TestCase
  test "a deck comparison keeps its title, its back link and its links to each deck" do
    html = render_view(Decks::CompareView.new(comparison: comparison))

    assert_includes html, "<h1>Compare Decks</h1>"
    assert_match %r{<a [^>]*href="/decks">Back to Decks</a>}, html
    assert_includes html, %(<a href="/decks/left-key">Left</a>)
    assert_includes html, %(<a href="/decks/right-key">Right</a>)
  end

  test "another page can retitle it and point its links elsewhere" do
    view = Decks::CompareView.new(
      comparison: comparison,
      title: "Honedge Box — v2",
      back_label: "Back to Versions",
      back_path: "/decks/left-key/versions",
      column_path: ->(deck) { "/decks/left-key/versions/#{deck.id}" }
    )
    html = render_view(view)

    assert_includes html, "<h1>Honedge Box — v2</h1>"
    assert_match %r{<a [^>]*href="/decks/left-key/versions">Back to Versions</a>}, html
    assert_includes html, %(<a href="/decks/left-key/versions/1">Left</a>)
    assert_includes html, %(<a href="/decks/left-key/versions/2">Right</a>)
    assert_no_match %r{href="/decks/(left|right)-key"}, html
  end

  private

  def comparison
    left = Deck.new(id: 1, key: "left-key", name: "Left")
    right = Deck.new(id: 2, key: "right-key", name: "Right")
    card = Card.new(id: 7, name: "Honedge", card_type: "Pokémon", set_name: "POR", set_number: "56")
    row = { card: card, name: "Honedge", quantities: { 1 => 2, 2 => 3 }, differ: true }

    {
      decks: [ left, right ],
      groups: [ { type: "Pokémon", rows: [ row ], differing: true, subtotals: [ 2, 3 ], diff_subtotals: [ 2, 3 ] } ],
      totals: [ 2, 3 ],
      diff_totals: [ 2, 3 ]
    }
  end

  def render_view(view)
    ApplicationController.renderer.render(view, layout: false)
  end
end
