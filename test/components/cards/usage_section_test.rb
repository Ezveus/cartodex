require "test_helper"

# Rendered through `ApplicationController.renderer`, like Cards::IndexViewTest, because the
# component resolves routes through a view_context. Built from hand-made structs: what is under
# test is how a node is printed and where it links, not how it was computed.
class Cards::UsageSectionTest < ActiveSupport::TestCase
  Usage = Cards::ArchetypeUsage::Usage

  test "each node links to the analysis with its own parameters, Other formats to nothing" do
    html = render_usage(tree)
    doc = Nokogiri::HTML5(html)
    archetype = archetypes(:ogerpon)

    hrefs = doc.css(".card-usage-link").map { |anchor| anchor["href"] }
    assert_equal [
      "/archetypes/#{archetype.to_param}/analysis?pool=all&venue=paper",
      "/archetypes/#{archetype.to_param}/analysis?pool=7&venue=paper",
      "/archetypes/#{archetype.to_param}/analysis?pool=7&tournament=9&venue=paper",
      "/archetypes/#{archetype.to_param}/analysis?pool=all&tournament=11&venue=paper"
    ], hrefs
    outside = doc.css(".card-usage-pool > details > summary").last
    assert_equal "Other formats", outside.at_css(".card-usage-name").text
    assert_empty outside.css("a")
  end

  test "a played node prints the share, the lists and the copies; a 0 % node says not played" do
    doc = Nokogiri::HTML5(render_usage(tree))
    figures = doc.css(".card-usage-figures").map(&:text)

    # The archetype line blends every rotation, as the analysis's "All formats" does, and says so.
    assert_equal "All formats · 33.3% · 1 of 3 lists · 1-2 copies · most often 1 / 2 — tied", figures[0]
    assert_equal "100% · 1 of 1 list · 1 copy", figures[1]
    assert_equal "100% · 1 of 1 list · 1 copy", figures[2]
    # Usage's nil copies make `single_quantity?` true — `nil == nil` — and CopiesText would print
    # " copies" for it. A node nobody plays must never reach that text.
    assert_equal "not played · 0 of 12 lists", figures[3]
    # "here", not "in this pool": the Other formats node is not a pool, and carries the same line.
    assert_equal [ "2 other tournaments here: not played.", "1 other tournament here: not played." ],
                 doc.css(".card-usage-unplayed").map(&:text)
  end

  test "the venue select renders only when both venues hold lists playing the card" do
    with = Nokogiri::HTML5(render_usage(tree))
    assert_equal %w[all paper online], with.css("select[name=venue] option").map { |option| option["value"] }
    assert_equal "paper", with.at_css("select[name=venue] option[selected]")["value"]
    assert_equal "/cards/#{cards(:budew_pre).id}#usage", with.at_css("form.card-usage-filters")["action"]

    without = Nokogiri::HTML5(render_usage(tree.tap { |result| result.venue_selectable = false }))
    assert_nil without.at_css("select[name=venue]")
  end

  test "a card no list plays says so" do
    empty = Cards::ArchetypeUsage::Result.new(venue: :all, venue_options: [], venue_selectable: false,
                                              archetypes: [])
    doc = Nokogiri::HTML5(render_usage(empty))

    assert_equal "No recorded list plays this card.", doc.at_css(".card-usage-empty").text
    assert_nil doc.at_css(".card-usage-tree")
  end

  private

  def render_usage(result)
    ApplicationController.renderer.render(Cards::UsageSection.new(card: cards(:budew_pre), usage: result),
                                          layout: false)
  end

  def usage(lists, playing, pct, min, max, modes)
    Usage.new(lists_count: lists, playing_count: playing, pct: pct, min_copies: min, max_copies: max, modes: modes)
  end

  def tree
    tournament = Cards::ArchetypeUsage::TournamentNode.new(
      tournament_id: 9, label: "Regional (6/1/2026)", usage: usage(1, 1, 100.0, 1, 1, [ 1 ]),
      analysis_params: { pool: "7", tournament: "9", venue: "paper" }
    )
    pool = Cards::ArchetypeUsage::PoolNode.new(
      pool_id: 7, label: "TWM-POR", usage: usage(1, 1, 100.0, 1, 1, [ 1 ]), tournaments: [ tournament ],
      unplayed_tournaments_count: 2, analysis_params: { pool: "7", venue: "paper" }
    )
    glc = Cards::ArchetypeUsage::TournamentNode.new(
      tournament_id: 11, label: "League Cup (4/1/2026)", usage: usage(1, 0, 0.0, nil, nil, []),
      analysis_params: { pool: "all", tournament: "11", venue: "paper" }
    )
    outside = Cards::ArchetypeUsage::PoolNode.new(
      pool_id: nil, label: "Other formats", usage: usage(12, 0, 0.0, nil, nil, []), tournaments: [ glc ],
      unplayed_tournaments_count: 1, analysis_params: nil
    )
    archetype = Cards::ArchetypeUsage::ArchetypeNode.new(
      archetype: archetypes(:ogerpon), usage: usage(3, 1, 33.3, 1, 2, [ 1, 2 ]),
      pools: [ pool, outside ], analysis_params: { pool: "all", venue: "paper" }
    )
    options = %w[all paper online].map { |value| Cards::ArchetypeUsage::Option.new(value: value, label: value) }
    Cards::ArchetypeUsage::Result.new(venue: :paper, venue_options: options, venue_selectable: true,
                                      archetypes: [ archetype ])
  end
end
