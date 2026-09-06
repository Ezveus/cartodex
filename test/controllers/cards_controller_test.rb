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

  # The same for a role, and it is not a symmetry test. `@searching` is one expression, so every
  # filter added to the page has to be added to it — and until this test existed, deleting
  # `|| @role` from it left all twelve of the others green while `/cards?role=gust` rendered the
  # browse prompt under a URL claiming to filter. The role half is the one the issue calls the
  # useful one, and it was the half with no isolated coverage.
  test "index filters by a role on its own" do
    label_card(gust_role, cards(:bosss_orders_meg))

    get cards_path(role: "gust")

    assert_response :success
    assert_select ".card-grid-name", text: "Boss's Orders", count: 1
    assert_select ".card-grid-name", text: "Honedge", count: 0
    assert_select "p.cards-empty", text: BROWSE_PROMPT, count: 0
  end

  # The question the issue's headline asks — "Item and gust" — crosses a column filter and a label
  # filter, which the two-label test above cannot exercise: it applies the same clause twice.
  test "a label narrows a column filter rather than being ANDed with nothing" do
    label_card(gust_role, cards(:bosss_orders_meg))
    label_card(gust_role, cards(:honedge))

    get cards_path(type: "Trainer", role: "gust")

    assert_select ".card-grid-name", text: "Boss's Orders", count: 1
    assert_select ".card-grid-name", { text: "Honedge", count: 0 },
      "a Pokémon survived a Trainer filter"
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
  # /cards is reachable with no session, so it receives whatever a crawler or a broken link sends.
  # This asserts the answer a malformed filter gets — 200 and no matches — and **not** the `to_s`
  # coercion in the controller, which it cannot: measured by sabotage, removing that `to_s` leaves
  # this green, because an unresolvable label matches nothing whatever its shape and the danger
  # (an `ActionController::Parameters` reaching `cards_path` and raising `UnfilteredParameters`)
  # lives in a pager that an empty result never renders. Reproducing that would take 49 matching
  # cards, which no fixture and no production label provides. So the `to_s` is defence in depth
  # against a failure mode nothing can currently exercise, and this test is about the answer.
  test "a hash- or array-shaped label answers no matches rather than raising" do
    ace_spec

    get cards_path(label: [ "ace-spec" ])
    assert_response :success
    assert_select "p.cards-empty", text: NO_MATCH

    get cards_path(role: { slug: "gust" })
    assert_response :success
    assert_select "p.cards-empty", text: NO_MATCH
  end

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

  # CardLabelAssignment.active is `rejected: false` and says nothing about provenance, so a rule's
  # guess and a human's decision open the same page. Archetypes::CardReport says so for the
  # member-only report; this surface is anonymous, and after one suggester run on the production
  # dump 714 of 743 assignments were guesses.
  test "a role filter says when it is showing a rule's proposals" do
    gust_role.assignments.create!(fingerprint: cards(:bosss_orders_meg).fingerprint,
                                  card: cards(:bosss_orders_meg), source: "suggested")

    get cards_path(role: "gust")

    assert_select "p.cards-search-note", text: /nobody has confirmed yet/
  end

  # And says nothing once every role it is showing was decided by a person — the same restraint
  # the provenance note on the archetype report shows.
  test "a role filter is silent once its roles were confirmed by hand" do
    gust_role.assignments.create!(fingerprint: cards(:bosss_orders_meg).fingerprint,
                                  card: cards(:bosss_orders_meg), source: "curated")

    get cards_path(role: "gust")

    assert_select ".card-grid-name", text: "Boss's Orders"
    assert_select "p.cards-search-note", count: 0
  end

  # A type label is imported from Limitless's own search, not guessed from card text, so there is
  # no proposal to disclaim.
  test "a type label says nothing about provenance" do
    label_card(ace_spec, cards(:bosss_orders_meg))

    get cards_path(label: "ace-spec")

    assert_select "p.cards-search-note", count: 0
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
