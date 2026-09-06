require "test_helper"

# The pager's URLs, which no controller test can reach: `Ui::Pagination` renders nothing under two
# pages, `PER_PAGE` is 48 and `cards.yml` holds thirteen cards, so a request that paginates a label
# filter is not constructible against the fixtures. (In production it very much is — a single
# suggester run puts 494 cards under `search` — which is why the pager has to be right and why
# this file exists at all.) Rendered through
# `ApplicationController.renderer` rather than a bare `.call` because the component uses `link_to`
# and `cards_path`, which resolve through a view_context (the trap Ui::ArchetypeBadgeTest
# documents); the precedent is Archetypes::SampleSelectorTest.
class Cards::IndexViewTest < ActiveSupport::TestCase
  # Every filter the bar carries has to survive a page turn. A param missing from
  # `search_query_params` does not fail loudly: page 2 renders the unfiltered catalogue under the
  # heading the reader was already reading.
  # They have to be re-emitted as **slugs**: a `CardLabel` record here would be serialised by
  # `to_param` into its id, which the next request cannot resolve back to a slug, so page 2 would
  # drop the filter while page 1 looked right. That hazard is closed upstream rather than here —
  # `CardsController` reads `params[:label].to_s`, so the value cannot be a record — and a
  # component handed a String could not demonstrate anything about one handed a record. The
  # assertion that would matter is the absence of a bare id, which this one implies.
  test "the pager re-emits every filter, so page two is the same search" do
    html = paginated(label: "ace-spec", role: "gust", query: "Budew", type: "Pokémon")

    assert_includes html, "label=ace-spec"
    assert_includes html, "role=gust"
    assert_includes html, "type=Pok"
    assert_includes html, "page=2"
    assert_no_match(/label=\d+&/, html, "a label reached the pager as an id rather than a slug")
  end

  private

  def paginated(label: nil, role: nil, query: "", type: nil)
    ApplicationController.renderer.render(
      Cards::IndexView.new(
        blocks: {}, current_set: nil, cards: [ cards(:budew_pre) ], query: query,
        type: type, energy: nil, rarity: nil, mark: nil, label: label, role: role,
        rarities: [], marks: [], labels: [], roles: [],
        searching: true, card_counts: {}, total: 60, page: 1, pages: 2
      ),
      layout: false
    )
  end
end
