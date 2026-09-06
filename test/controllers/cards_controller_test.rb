require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
  end

  test "index without params shows the empty prompt and the search form" do
    get cards_path

    assert_response :success
    assert_select "p.cards-empty"
    assert_select "form.cards-search"
  end

  test "index filters by name" do
    get cards_path(q: "Honedge")

    assert_response :success
    assert_select ".card-grid-name", text: "Honedge"
    assert_select ".card-grid-name", { text: "Doublade", count: 0 }
  end

  test "index filters by card type" do
    get cards_path(type: "Trainer")

    assert_response :success
    assert_select ".card-grid-name", text: "Boss's Orders", minimum: 1
    assert_select ".card-grid-name", { text: "Honedge", count: 0 }
  end

  test "index filters by energy type" do
    get cards_path(energy: "Metal")

    assert_response :success
    assert_select ".card-grid-name", text: "Honedge"
    assert_select ".card-grid-name", { text: "Budew", count: 0 }
  end

  test "index filters by regulation mark" do
    get cards_path(mark: "H")

    assert_response :success
    assert_select ".card-grid-name", text: "Budew", count: 1
  end

  test "index restricts search to the selected set" do
    get cards_path(q: "Honedge", set: card_sets(:por).code)

    assert_response :success
    assert_select ".card-grid-name", text: "Honedge", count: 1
  end

  test "index returns nothing when search is scoped to an unrelated set" do
    get cards_path(q: "Honedge", set: card_sets(:asc).code)

    assert_response :success
    assert_select "p.cards-empty"
  end

  test "index parses name, set code and number tokens together" do
    get cards_path(q: "Budew ASC 16")

    assert_response :success
    assert_select ".card-grid-name", text: "Budew", count: 1
  end

  test "index without a search shows the selected set grid" do
    get cards_path(set: card_sets(:por).code)

    assert_response :success
    assert_select "turbo-frame#card_results h2", text: card_sets(:por).name
  end

  test "index treats LIKE metacharacters in the query as literals" do
    get cards_path(q: "b_dew")

    assert_response :success
    assert_select ".card-grid-name", { text: "Budew", count: 0 }, "_ must not act as a wildcard"

    get cards_path(q: "bud%w")

    assert_response :success
    assert_select ".card-grid-name", { text: "Budew", count: 0 }, "% must not act as a wildcard"
  end

  test "the cards index does not instantiate the catalog to count it" do
    get cards_path # warm the session and the caches

    assert_no_difference -> { Card.count } do
      # The guard is on rows instantiated, not queries: the sidebar needs a count per set,
      # and includes(:cards) built every Card object in the database to get it.
      records = 0
      subscriber = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
        records += payload[:record_count] if payload[:class_name] == "Card"
      end
      get cards_path
      ActiveSupport::Notifications.unsubscribe(subscriber)

      assert_equal 0, records, "the index instantiated #{records} Card objects without a search"
    end
    assert_response :success
  end

  test "the sidebar still shows a card count per set" do
    get cards_path

    assert_response :success
    assert_select ".set-code", text: /\(\d+\)/
  end

  # --- Filtering by card label (issue #164) ----------------------------------------------------
  #
  # Every assertion below reads the empty state's **text**, never `p.cards-empty`: the same class
  # carries "Select a set or search to browse cards." and "No cards match your search.", so the
  # class alone cannot tell a filter that ran and matched nothing from one the page never applied.
  # Both pre-existing empty-state tests above are class-only for that reason and cannot help here.
  #
  # There are no label fixtures — every label test in the suite builds its own rows.

  BROWSE_PROMPT = "Select a set or search to browse cards.".freeze
  NO_MATCH = "No cards match your search.".freeze

  test "index filters by a type label, and does not fall through to the whole catalog" do
    label_card(ace_spec, cards(:bosss_orders_meg))

    get cards_path(label: "ace-spec")

    assert_response :success
    assert_select ".card-grid-name", text: "Boss's Orders", count: 1
    # The other wrong implementation — the param filtering nothing while `@searching` is true —
    # renders a page of the unfiltered catalogue and no empty state at all, so asserting the
    # absence of a browse prompt would not see it.
    assert_select ".card-grid-name", text: "Honedge", count: 0
  end

  # `set` is deliberately outside `@searching`, so before this change `?set=…&label=…` rendered the
  # whole set — and "index without a search shows the selected set grid" asserts exactly that
  # output as correct, which is why nothing in the suite could report the omission.
  test "a label narrows a selected set rather than being ignored by it" do
    label_card(ace_spec, cards(:honedge))

    get cards_path(set: card_sets(:por).code, label: "ace-spec")

    assert_response :success
    assert_select ".card-grid-item", count: 1
    assert_select ".card-grid-name", text: "Honedge"
  end

  # A curated refusal is a row, not an absence. Forgotten, the filter lists exactly the cards a
  # human said the label does not describe. CardLabelAssignmentTest guards the `active` scope and
  # stays green whatever this controller calls.
  test "a rejected assignment is not a label" do
    label = ace_spec
    label_card(label, cards(:bosss_orders_meg))
    label.assignments.create!(fingerprint: cards(:honedge).fingerprint, card: cards(:honedge),
                              source: "curated", rejected: true)

    get cards_path(label: "ace-spec")

    assert_select ".card-grid-name", text: "Boss's Orders", count: 1
    assert_select ".card-grid-name", text: "Honedge", count: 0
  end

  # The assignment names a fingerprint, not a printing: every printing of Prime Catcher is an ACE
  # SPEC. `budew_pre` and `budew_asc` already share `budew_shared`, so an assignment naming one
  # must return both — keyed on `card_id` it returns one and nothing in the suite notices.
  test "a label reaches every printing of the card, not the one it was recorded from" do
    label_card(ace_spec, cards(:budew_pre))

    get cards_path(label: "ace-spec")

    assert_select ".card-grid-name", text: "Budew", count: 2
  end

  # Two filters must AND. `merge` — the idiom `CardSearchable#apply_card_name_filter` uses three
  # lines away — keeps only the last of two `where`s on one column, so it answers "gust" alone.
  #
  # **Three cards, and the third is the whole test.** A card carrying only the *first* label is
  # excluded by both the right rule and the wrong one, so a fixture holding only those two proves
  # nothing — measured: sabotaging the chain into a `merge` left it green. What tells them apart is
  # a card carrying only the **second**, which `merge` lets through.
  test "a type label and a role narrow each other rather than replacing each other" do
    ace, gust = ace_spec, gust_role
    label_card(ace, cards(:budew_pre))
    label_card(gust, cards(:budew_pre))
    label_card(ace, cards(:honedge))
    label_card(gust, cards(:doublade))

    get cards_path(label: "ace-spec", role: "gust")

    assert_select ".card-grid-name", text: "Budew", count: 2
    assert_select ".card-grid-name", text: "Honedge", count: 0
    assert_select ".card-grid-name", { text: "Doublade", count: 0 },
      "the role filter replaced the label filter instead of narrowing it"
  end

  test "an unknown label answers no matches rather than the browse prompt" do
    ace_spec

    get cards_path(label: "not-a-label")

    assert_response :success
    assert_select "p.cards-empty", text: NO_MATCH
  end

  # The filter bar sits outside the Turbo Frame the form targets, so it is never re-rendered by a
  # keystroke: the only thing that exercises the selected state is a shared link or a bookmark. A
  # control comparing the wrong things filters correctly and reads "All labels".
  test "the label select says which label is showing" do
    ace_spec

    get cards_path(label: "ace-spec")

    assert_select "select[name=label] option[selected][value=?]", "ace-spec"
  end

  # A select whose only option is "All labels" is not a choice — MetagameScope::Result#selectable?'s
  # rule. Both halves are asserted, because with no label fixtures the absent case is the default
  # and would pass against an implementation that never renders the control at all.
  test "a family with no labels renders no control, and one with a label renders one" do
    get cards_path

    assert_select "select[name=label]", count: 0
    assert_select "select[name=role]", count: 0

    ace_spec
    gust_role
    get cards_path

    assert_select "select[name=label] option", text: "ACE SPEC"
    assert_select "select[name=role] option", text: "Gust"
  end

  # /cards is public and rate-limited at 60/min per IP, so the two option lists must not put a
  # query per request back on it. A relative comparison could never see it: both lists are one and
  # seven rows whatever the catalogue holds, so an unloaded relation asked `any?` before `each`
  # costs exactly two extra queries, always. Hence a literal — measured with the labels created,
  # since the default fixtures render neither control.
  #
  # Traced, so the literal is a breakdown rather than a number: Warden reloading the signed-in user
  # (which happens on **every** request of an integration test, not only the first — a "warm the
  # session" first call does not remove it), the sets sidebar, the grouped count per set, the two
  # unindexed `DISTINCT` scans behind Card.filter_values — never cached here, since the test
  # environment's store is :null_store — and then exactly two reads of `card_labels`, one per
  # family.
  test "the label vocabularies cost one query each" do
    ace_spec
    gust_role
    get cards_path

    assert_equal 7, count_queries { get cards_path },
      "the label option lists are being re-read per render"
  end

  private

  def ace_spec
    @ace_spec ||= CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
  end

  def gust_role
    @gust_role ||= CardLabel.create!(slug: "gust", name: "Gust", family: "role", position: 30)
  end

  def label_card(label, card)
    label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")
  end
end
