require "test_helper"

# The pager's URLs, which no controller test can reach: `Ui::Pagination` renders nothing under two
# pages, `PER_PAGE` is 48, the fixtures hold fourteen cards, and the largest label in production
# reaches 33 — so a request that paginates a label filter is not constructible. Rendered through
# `ApplicationController.renderer` rather than a bare `.call` because the component uses `link_to`
# and `cards_path`, which resolve through a view_context (the trap Ui::ArchetypeBadgeTest
# documents); the precedent is Archetypes::SampleSelectorTest.
class Cards::IndexViewTest < ActiveSupport::TestCase
  # Every filter the bar carries has to survive a page turn. A param missing from
  # `search_query_params` does not fail loudly: page 2 renders the unfiltered catalogue under the
  # heading the reader was already reading.
  test "the pager re-emits every filter, so page two is the same search" do
    html = paginated(label: "ace-spec", role: "gust", query: "Budew", type: "Pokémon")

    assert_includes html, "label=ace-spec"
    assert_includes html, "role=gust"
    assert_includes html, "type=Pok"
    assert_includes html, "page=2"
  end

  # And they have to be re-emitted as slugs. A `CardLabel` record here would be serialised by
  # `to_param` into its id, which the next request cannot resolve back to a slug — so page 2 would
  # drop the filter while page 1 looked right, and no assertion on page 1 could see it.
  test "the pager emits a label as its slug, never as a record" do
    html = paginated(label: "ace-spec")

    assert_includes html, "label=ace-spec"
    assert_no_match(/label=\d/, html)
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
