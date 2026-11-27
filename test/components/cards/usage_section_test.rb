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

  # Collapsed, as the class says: the widest card has 1383 nodes, and the first level is what a
  # reader scans. And a pool whose every event plays the card prints no "0 other tournaments" line.
  test "every node starts collapsed and an all-played pool prints no unplayed line" do
    result = tree
    result.archetypes.first.pools.first.unplayed_tournaments_count = 0
    result.archetypes.first.pools.last.unplayed_tournaments_count = 0
    doc = Nokogiri::HTML5(render_usage(result))

    assert_operator doc.css("details").size, :>, 0
    assert_empty doc.css("details[open]")
    assert_empty doc.css(".card-usage-unplayed")
    assert_no_match(/other tournament/, doc.text)
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
    doc = Nokogiri::HTML5(render_usage(result))

    assert_equal "No recorded list plays this card.", doc.at_css(".card-usage-empty").text
    assert_nil doc.at_css(".card-usage-tree")
    assert_nil doc.at_css("form.card-usage-filters"), "no select is a choice, so no form"
  end

  # Each select renders on its own axis's rule, in the analysis's order, and marks the resolved
  # value — a select built without it pre-selects its first option, "TWM-POR" here, above a tree
  # showing All formats.
  test "the pool and tournament selects render on their own rules and mark the resolved values" do
    pool_only = Nokogiri::HTML5(render_usage(result(pool_selectable: true)))
    assert_equal [ "pool" ], pool_only.css("form.card-usage-filters select").map { |select| select["name"] }
    assert_equal "all", pool_only.at_css("select[name=pool] option[selected]")["value"]

    pool = StandardPool.new(id: 7)
    all = Nokogiri::HTML5(render_usage(result(pool: pool, pool_selectable: true, venue: :online,
                                              venue_selectable: true, tournament_id: 10,
                                              tournament_selectable: true)))
    assert_equal %w[pool venue tournament], all.css("form.card-usage-filters select").map { |select| select["name"] }
    assert_equal [ "7", "online", "10" ], all.css("option[selected]").map { |option| option["value"] }
    assert_equal [ "Standard pool", "Venue", "Tournament" ], all.css(".archetype-sample-label > span").map(&:text)

    tournament_only = Nokogiri::HTML5(render_usage(result(venue_selectable: true, tournament_selectable: true)))
    assert_equal "all", tournament_only.at_css("select[name=tournament] option[selected]")["value"]
    assert_equal %w[venue tournament], tournament_only.css("form.card-usage-filters select").map { |select| select["name"] },
                 "a pool select that is no choice is not rendered beside the others"
  end

  # Each archetype links to its own analysis — the base path is built once per archetype, and a
  # cache keyed on anything else would send every row to the first one's page.
  test "each archetype's link names its own archetype" do
    leaves = [ archetypes(:ogerpon), Archetype.where.not(id: archetypes(:ogerpon).id).first ].map do |archetype|
      Cards::ArchetypeUsage::ArchetypeNode.new(
        archetype: archetype, usage: usage(1, 1, 100.0, 1, 1, [ 1 ]), scope_label: nil, pools: [], tournaments: [],
        unplayed_tournaments_count: 0, analysis_params: { pool: "all", tournament: "9" }
      )
    end
    doc = Nokogiri::HTML5(render_usage(result(archetypes: leaves)))

    assert_equal leaves.map { |node| "/archetypes/#{node.archetype.to_param}/analysis?pool=all&tournament=9" },
                 doc.css(".card-usage-link").map { |anchor| anchor["href"] }
  end

  # Under one pool an archetype opens onto its events directly; under one tournament it is a leaf.
  test "an archetype opens onto its events under a pool and is a leaf under a tournament" do
    event = Cards::ArchetypeUsage::TournamentNode.new(
      tournament_id: 9, label: "Regional (6/1/2026)", usage: usage(1, 1, 100.0, 1, 1, [ 1 ]),
      analysis_params: { pool: "7", tournament: "9" }
    )
    in_pool = Cards::ArchetypeUsage::ArchetypeNode.new(
      archetype: archetypes(:ogerpon), usage: usage(2, 1, 50.0, 1, 1, [ 1 ]), scope_label: "TWM-POR",
      pools: [], tournaments: [ event ], unplayed_tournaments_count: 1, analysis_params: { pool: "7" }
    )
    doc = Nokogiri::HTML5(render_usage(result(archetypes: [ in_pool ])))
    assert_equal "TWM-POR · 50% · 1 of 2 lists · 1 copy",
                 doc.at_css(".card-usage-archetype > details > summary .card-usage-figures").text
    assert_equal [ "Regional (6/1/2026)" ],
                 doc.css(".card-usage-archetype > details > .card-usage-children > .card-usage-tournament .card-usage-name").map(&:text)
    assert_equal "1 other tournament here: not played.", doc.at_css(".card-usage-unplayed").text

    leaf = Cards::ArchetypeUsage::ArchetypeNode.new(
      archetype: archetypes(:ogerpon), usage: usage(2, 1, 50.0, 1, 1, [ 1 ]), scope_label: nil,
      pools: [], tournaments: [], unplayed_tournaments_count: 0, analysis_params: { pool: "7", tournament: "9" }
    )
    doc = Nokogiri::HTML5(render_usage(result(archetypes: [ leaf ])))
    assert_empty doc.css("details")
    assert_equal "50% · 1 of 2 lists · 1 copy", doc.at_css(".card-usage-archetype > .card-usage-figures").text
    assert_equal "/archetypes/#{archetypes(:ogerpon).to_param}/analysis?pool=7&tournament=9",
                 doc.at_css(".card-usage-archetype > .card-usage-link")["href"]
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
      archetype: archetypes(:ogerpon), usage: usage(3, 1, 33.3, 1, 2, [ 1, 2 ]), scope_label: "All formats",
      pools: [ pool, outside ], tournaments: [], unplayed_tournaments_count: 0,
      analysis_params: { pool: "all", venue: "paper" }
    )
    result(venue: :paper, venue_selectable: true, archetypes: [ archetype ])
  end

  def result(**overrides)
    Cards::ArchetypeUsage::Result.new(
      pool: nil, pool_options: options(%w[7 all]), pool_selectable: false,
      venue: :all, venue_options: options(%w[all paper online]), venue_selectable: false,
      tournament_id: nil, tournament_options: options(%w[all 9 10]), tournament_selectable: false,
      archetypes: [], **overrides
    )
  end

  def options(values)
    values.map { |value| Cards::ArchetypeUsage::Option.new(value: value, label: "#{value} label") }
  end
end
