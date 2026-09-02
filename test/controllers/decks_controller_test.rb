require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Original", description: "Desc")
    sign_in @user
  end

  test "edit renders the show page with the edit frame" do
    get edit_deck_path(@deck)

    assert_response :success
    assert_select "turbo-frame#deck-header form"
  end

  test "update with valid params renders the frame in display mode" do
    patch deck_path(@deck), params: { deck: { name: "Renamed", description: "New" } }

    assert_response :success
    assert_select "turbo-frame#deck-header h1", text: "Renamed"
    assert_equal "Renamed", @deck.reload.name
    assert_equal "New", @deck.description
  end

  test "update with invalid params re-renders the form with errors" do
    patch deck_path(@deck), params: { deck: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#deck-header form"
    assert_equal "Original", @deck.reload.name
  end

  test "destroy removes the deck and redirects to index" do
    assert_difference -> { Deck.count }, -1 do
      delete deck_path(@deck)
    end

    assert_redirected_to decks_path
  end

  test "destroy cascades to deck_cards and deck_results" do
    @deck.deck_cards.destroy_all
    @deck.deck_results.destroy_all
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
    @deck.deck_results.create!(result: "win", played_at: Time.current)

    assert_difference [ -> { DeckCard.count }, -> { DeckResult.count } ], -1 do
      delete deck_path(@deck)
    end
  end

  test "duplicate creates a new deck and redirects to it" do
    assert_difference -> { Deck.count }, 1 do
      post duplicate_deck_path(@deck)
    end

    new_deck = Deck.order(:id).last
    assert_redirected_to deck_path(new_deck)
    assert_equal "Copy of Original", new_deck.name
  end

  test "update persists the classification fields" do
    patch deck_path(@deck), params: { deck: {
      name: "Classified", physical: "1", tcg_live: "1",
      format: "expanded"
    } }

    assert_response :success
    @deck.reload
    assert @deck.physical?
    assert @deck.tcg_live?
    assert @deck.expanded?
  end

  # The new-deck form is where a Standard deck's anchor is actually chosen; deck_params must
  # permit it or every Standard deck created through the form would 422.
  test "create persists an explicit standard pool" do
    post decks_path, params: { deck: {
      name: "New Standard Deck", format: "standard", standard_pool_id: standard_pools(:twm_asc).id
    } }

    new_deck = Deck.order(:id).last
    assert_redirected_to deck_path(new_deck)
    assert_equal standard_pools(:twm_asc), new_deck.standard_pool
  end

  # On the show page the allocation steppers change what the badge derives from without a reload,
  # so the badge ships on every load and `deck-proxies` toggles it. It therefore has to be in the
  # markup — hidden — even for a deck that currently holds no proxy.
  test "show renders the proxies badge hidden when the deck is fully backed" do
    @deck.update!(physical: true)
    @deck.deck_cards.update_all(owned_copies: 1)

    get deck_path(@deck)

    assert_response :success
    assert_select "turbo-frame#deck-header [data-deck-proxies-target='badge'][hidden]"

    # The badge and the steppers that move it sit in different subtrees, so the relay only works if
    # the listener is registered on their common ancestor under the exact event name the two
    # stepper controllers dispatch (`dispatch("changed", { prefix: "deck-proxies" })`).
    assert_select ".deck-show-container[data-controller~='deck-proxies']" \
                  "[data-action*='deck-proxies:changed->deck-proxies#toggle']"
  end

  test "show renders the proxies badge visible when the deck holds a proxy" do
    @deck.update!(physical: true)

    get deck_path(@deck)

    assert_response :success
    assert_select "turbo-frame#deck-header [data-deck-proxies-target='badge']"
    assert_select "turbo-frame#deck-header [data-deck-proxies-target='badge'][hidden]", false
  end

  test "the deck page hands its javascript the key, not the id" do
    get deck_path(@deck)

    assert_response :success
    # A String landing in a controller that still declares `deckId: Number` coerces to NaN
    # and dies in a fetch catch, so these attributes are the JS half of the identity change
    # and nothing else in the suite reads them.
    assert_select "[data-result-modal-deck-key-value=?]", @deck.key
    assert_select "[data-card-search-deck-key-value=?]", @deck.key
    assert_select "[data-deck-card-quantity-deck-key-value=?]", @deck.key
    assert_select "[data-tournament-pdf-deck-key-value=?]", @deck.key
    assert_select "[data-result-modal-deck-id-value]", count: 0
  end

  # The deck list has no such steppers, so it keeps a plain server-rendered badge — no hidden
  # element to toggle, no target attribute on the dozens of decks it renders.
  test "index omits the proxies badge entirely for a fully backed deck" do
    @deck.update!(physical: true)
    @deck.deck_cards.update_all(owned_copies: 1)

    get decks_path

    assert_response :success
    assert_select "#deck-#{@deck.id} [data-deck-proxies-target='badge']", false
    assert_select "#deck-#{@deck.id} .badge-warning", false
  end

  test "index filters decks by format" do
    @deck.update!(format: "expanded")
    other = @user.decks.create!(name: "Std deck", format: "standard", standard_pool: standard_pools(:twm_por))

    get decks_path(format: "expanded")

    assert_response :success
    assert_select "#deck-#{@deck.id}"
    assert_select "#deck-#{other.id}", false
  end

  test "index filters decks by support and proxies" do
    @deck.update!(physical: true)
    # The fixture deck_card is backed off, so the proxy this filter must catch is the one below and
    # nothing else — otherwise the test would pass against a scope that ignores owned_copies.
    @deck.deck_cards.update_all(owned_copies: 1)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2, owned_copies: 1)
    live = @user.decks.create!(name: "Live deck", tcg_live: true, standard_pool: standard_pools(:twm_por))

    get decks_path(support: "physical", proxies: "with")

    assert_response :success
    assert_select "#deck-#{@deck.id}"
    assert_select "#deck-#{live.id}", false
  end

  # The "without" half is not the complement of a stored flag any more but of a subquery, so it
  # gets its own coverage: a fully-backed physical deck and a TCG Live deck both belong here.
  test "index filters decks without proxies" do
    @deck.update!(physical: true)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2, owned_copies: 1)
    backed = @user.decks.create!(name: "Backed deck", physical: true, standard_pool: standard_pools(:twm_por))
    backed.deck_cards.create!(card: cards(:honedge), quantity: 1, owned_copies: 1)
    # Unbacked cards on purpose: a TCG Live deck's cards always sit at owned_copies 0, so this is
    # what a scope missing its `physical` half would wrongly file under "with proxies".
    live = @user.decks.create!(name: "Live deck", tcg_live: true, standard_pool: standard_pools(:twm_por))
    live.deck_cards.create!(card: cards(:doublade), quantity: 2)

    get decks_path(proxies: "without")

    assert_response :success
    assert_select "#deck-#{backed.id}"
    assert_select "#deck-#{live.id}"
    assert_select "#deck-#{@deck.id}", false
  end

  test "index filters decks by primary Pokémon" do
    @deck.update!(archetype: archetypes(:budew_ogerpon))
    other = @user.decks.create!(name: "No archetype", standard_pool: standard_pools(:twm_por))

    get decks_path(primary: cards(:budew_pre).id)

    assert_response :success
    assert_select "#deck-#{@deck.id}"
    assert_select "#deck-#{other.id}", false
  end

  test "index filters decks by secondary Pokémon" do
    @deck.update!(archetype: archetypes(:budew_ogerpon))
    other = @user.decks.create!(name: "Primary only", archetype: archetypes(:ogerpon), standard_pool: standard_pools(:twm_por))

    get decks_path(secondary: cards(:teal_mask_ogerpon_ex).id)

    assert_response :success
    assert_select "#deck-#{@deck.id}"
    assert_select "#deck-#{other.id}", false
  end

  test "compare renders a comparison of the selected decks" do
    other = @user.decks.create!(name: "Other", standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)
    other.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 1)

    get compare_decks_path(ids: [ @deck.key, other.key ])

    assert_response :success
    assert_select ".deck-compare-table"
    assert_select ".deck-compare-table thead th", text: "Original"
  end

  test "compare redirects when fewer than two decks are selected" do
    get compare_decks_path(ids: [ @deck.key ])

    assert_redirected_to decks_path
  end

  test "compare ignores decks belonging to other users" do
    get compare_decks_path(ids: [ @deck.key, decks(:two).key ])

    assert_redirected_to decks_path
  end

  test "the compare checkbox carries the key" do
    get decks_path

    assert_response :success
    assert_select ".deck-compare-checkbox[value=?]", @deck.key
  end

  test "update assigns an archetype to the deck" do
    patch deck_path(@deck), params: { deck: { name: "Tagged", archetype_id: archetypes(:ogerpon).id } }

    assert_response :success
    assert_equal archetypes(:ogerpon), @deck.reload.archetype
  end

  test "matchups groups the user's decks by archetype" do
    @deck.update!(archetype: archetypes(:ogerpon))
    @deck.deck_results.destroy_all
    @deck.deck_results.create!(result: "win", played_at: Time.current)

    get matchups_decks_path

    assert_response :success
    assert_select "h2", text: archetypes(:ogerpon).name
  end

  test "cannot edit another user's deck" do
    get edit_deck_path(decks(:two))

    assert_response :not_found
  end

  test "cannot destroy another user's deck" do
    assert_no_difference -> { Deck.count } do
      delete deck_path(decks(:two))
    end

    assert_response :not_found
  end

  test "cannot duplicate another user's deck" do
    assert_no_difference -> { Deck.count } do
      post duplicate_deck_path(decks(:two))
    end

    assert_response :not_found
  end

  test "tournament_pdf export returns a PDF" do
    profile = tournament_profiles(:ash)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 1)

    get export_deck_path(@deck, style: "tournament_pdf", profile_id: profile.id)

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert @deck.name.parameterize.present?
    assert_match(/decklist\.pdf/, response.headers["Content-Disposition"])
    assert response.body.start_with?("%PDF")
  end

  test "tournament_pdf export rejects another user's profile" do
    other_profile = tournament_profiles(:giovanni)

    get export_deck_path(@deck, style: "tournament_pdf", profile_id: other_profile.id)

    assert_response :not_found
  end

  test "index filters decks by name" do
    @deck.update!(name: "Ogerpon Toolbox")
    other = @user.decks.create!(name: "Charizard Pidgeot", standard_pool: standard_pools(:twm_por))

    get decks_path(q: "ogerpon")

    assert_response :success
    assert_select "#decks-grid", text: /Ogerpon Toolbox/
    assert_select "#decks-grid", text: /Charizard Pidgeot/, count: 0
    assert_not_nil other
  end

  test "index finds a deck through its archetype" do
    @deck.update!(name: "Tuesday List", archetype: archetypes(:ogerpon))

    get decks_path(q: "ogerpon")

    assert_response :success
    assert_select "#decks-grid", text: /Tuesday List/
  end

  test "index ignores a blank q" do
    @deck.update!(name: "Ogerpon Toolbox")

    get decks_path(q: "   ")

    assert_response :success
    assert_select "#decks-grid", text: /Ogerpon Toolbox/
  end

  test "index keeps the query in the search field" do
    get decks_path(q: "ogerpon")

    assert_select "form.deck-filters input[name=q][value=ogerpon]"
  end

  # The filter form targets this frame (instead of a full-page visit) so the search field
  # survives the live-filtering debounce — see Decks::IndexView::FRAME_ID.
  test "index wraps the deck grid in a turbo frame the filter form targets" do
    get decks_path

    assert_response :success
    assert_select "turbo-frame#deck_results #decks-grid"
    assert_select "form.deck-filters[data-turbo-frame=deck_results][data-turbo-action=replace]"
  end

  # The spotlight renders "See all N decks" from Search::Global; this page must then show N.
  test "index shows exactly as many decks as the spotlight's total promises" do
    @deck.update!(name: "Ogerpon Toolbox")
    @user.decks.create!(name: "Ogerpon Build", standard_pool: standard_pools(:twm_por))

    get decks_path(q: "ogerpon")

    assert_response :success
    assert_equal Search::Global.call(user: @user, query: "ogerpon").deck_total,
      css_select("#decks-grid .deck-item").size
  end

  test "a q request renders the matching decks inside the turbo frame" do
    @deck.update!(name: "Ogerpon Toolbox")
    other = @user.decks.create!(name: "Charizard Pidgeot", standard_pool: standard_pools(:twm_por))

    get decks_path(q: "ogerpon")

    assert_response :success
    assert_select "turbo-frame#deck_results #deck-#{@deck.id}"
    assert_select "turbo-frame#deck_results #deck-#{other.id}", false
  end

  # The spotlight orders its five decks by name, so the page behind "See all N decks" has to open
  # with the same rows — creation order would show the user a different five.
  test "index lists decks in the order the spotlight promised" do
    @deck.update!(name: "Zoroark Toolbox")
    @user.decks.create!(name: "Ancient Toolbox", standard_pool: standard_pools(:twm_por))
    @user.decks.create!(name: "Miraidon Toolbox", standard_pool: standard_pools(:twm_por))

    get decks_path(q: "toolbox")

    assert_response :success
    grid = css_select("#decks-grid .deck-item").map { |item| item["id"].delete_prefix("deck-").to_i }
    spotlight = Search::Global.call(user: @user, query: "toolbox").decks.map(&:id)

    assert_equal spotlight, grid.first(spotlight.size)
  end

  # Turbo keeps #deck_results and discards the rest of the response, so the import banner and the
  # filter bar's two option lists must not be queried for a keystroke.
  test "a frame request skips the queries that only feed the page outside the frame" do
    get decks_path # warm the session: the first request of a test also loads the Devise user

    page = count_queries { get decks_path }
    frame = count_queries { get decks_path, headers: { "Turbo-Frame" => "deck_results" } }

    assert_response :success
    assert_operator frame, :<, page,
      "a frame request costs as much as the whole page: #{frame} vs #{page}"
  end

  test "a frame request still renders the filtered grid" do
    @deck.update!(name: "Ogerpon Toolbox")
    other = @user.decks.create!(name: "Charizard Pidgeot", standard_pool: standard_pools(:twm_por))

    get decks_path(q: "ogerpon"), headers: { "Turbo-Frame" => "deck_results" }

    assert_response :success
    assert_select "turbo-frame#deck_results #deck-#{@deck.id}"
    assert_select "turbo-frame#deck_results #deck-#{other.id}", false
  end

  # The filter bar renders outside deck_results, so live filtering never re-renders it: the link
  # ships in both states and the card-filter controller flips `hidden` as the fields change.
  test "index renders the Clear link hidden when no filter is set" do
    get decks_path

    assert_select "form.deck-filters a[data-card-filter-target=clear][hidden]"
  end

  test "index renders the Clear link visible when a filter is set" do
    get decks_path(q: "ogerpon")

    assert_select "form.deck-filters a[data-card-filter-target=clear]"
    assert_select "form.deck-filters a[data-card-filter-target=clear][hidden]", count: 0
  end

  # The deck show page ran one Availability lookup per deck card, with
  # excluding_deck set, so its cost grew with the decklist.
  test "show issues a constant number of queries regardless of decklist size" do
    deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
    @user.collections.find_or_create_by!(card: cards(:honedge)) { |c| c.quantity = 0 }.update!(quantity: 4)
    deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)
    # Both of these pin a branch across the two measurements: OverAllocations returns early when
    # nothing is over-allocated, and Cards::Printings.swappable_card_ids returns early when no card
    # on the page carries a fingerprint — and the cards the decklist grows by do carry one. Without
    # them, a measurement that crossed either branch would report a growth that is not an N+1.
    force_over_allocation(@user)
    deck.deck_cards.create!(card: cards(:budew_asc), quantity: 1)

    get deck_path(deck) # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get deck_path(deck) }

    grow_collection(@user).each { |card| deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 1) }

    large = count_queries { get deck_path(deck) }

    assert_response :success
    assert_equal small, large, "query count grew with the decklist: #{small} -> #{large}"
  end

  # The format badge names the deck's Standard pool, and StandardPool#name reads both of
  # the pool's card-set bounds — so an unpreloaded index cost three extra queries per
  # Standard deck. Each deck gets a pool of its own on purpose: decks sharing a pool id
  # issue identical SQL, which the per-request query cache serves and count_queries does
  # not count, hiding the very N+1 this guards.
  test "index issues a constant number of queries regardless of how many decks" do
    2.times { |i| @user.decks.create!(name: "Extra #{i}", standard_pool: pool_of_its_own(i)) }

    get decks_path # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get decks_path }

    (2..7).each { |i| @user.decks.create!(name: "Extra #{i}", standard_pool: pool_of_its_own(i)) }

    large = count_queries { get decks_path }

    assert_response :success
    assert_equal small, large, "query count grew with the deck count: #{small} -> #{large}"
  end

  test "the new deck form offers the standard pools, current one selected" do
    get new_deck_path

    assert_response :success
    assert_match "TWM-POR", response.body
    assert_match "TWM-ASC", response.body
  end

  # There is nothing to be stale about on a creation form — a new deck has no
  # anchor yet to compare against StandardPool.current.
  test "the new deck form shows no stale-anchor notice" do
    get new_deck_path

    assert_response :success
    assert_select ".standard-pool-notice", count: 0
  end

  # A rejected create re-renders :new with an unsaved Deck that already carries
  # whatever standard_pool_id was submitted — unlike a bare `get new_deck_path`,
  # this record is not anchor-less, so it is the one real path that isolates the
  # "never on a creation form" guard from the "no anchor at all" guard: without
  # the persisted? check, this deck would get nagged about a pool choice it
  # hasn't even saved yet.
  test "a rejected new deck is not nagged about its unsaved pool choice" do
    post decks_path, params: {
      deck: { name: "", format: "standard", standard_pool_id: standard_pools(:twm_asc).id }
    }

    assert_response :unprocessable_entity
    assert_select ".standard-pool-notice", count: 0
  end

  # Pinned means pinned: nothing moves the anchor on its own, so the only way a
  # user learns a newer Standard exists is being told while editing.
  #
  # ClassificationFields only renders inside the header's edit form, which the
  # show action never puts on the page (@editing is false there) — only the
  # edit action does (@editing is true, rendering the :show template). Hence
  # edit_deck_path, not deck_path.
  test "editing a deck anchored to an older pool invites an update" do
    decks(:one).update!(format: "standard", standard_pool: standard_pools(:twm_asc))

    get edit_deck_path(decks(:one))

    assert_response :success
    assert_match "TWM-ASC", response.body
    assert_match "TWM-POR", response.body
    assert_match "released since", response.body
  end

  test "a deck on the current pool is not nagged" do
    decks(:one).update!(format: "standard", standard_pool: StandardPool.current)

    get edit_deck_path(decks(:one))

    assert_response :success
    assert_no_match "released since", response.body
  end

  # Isolates the "no anchor at all" guard from the "new record" guard: this deck
  # is persisted (so @record.persisted? does not block it), it just has no
  # standard_pool. Fixtures always ship with one, and the model validates its
  # presence on a standard-format deck, so the only way to reach this state is
  # to bypass validation the way the rest of the suite does (e.g.
  # test/models/card_test.rb's save(validate: false)) — it is the pre-backfill
  # state a real row could be left in, not something the form can produce.
  test "a persisted deck with no anchor yet is not nagged" do
    deck = decks(:one)
    deck.format = "standard"
    deck.standard_pool = nil
    deck.save(validate: false)

    get edit_deck_path(deck)

    assert_response :success
    assert_select ".standard-pool-notice", count: 0
  end

  private

  # A pool nothing else shares, so that a page rendering N decks has N pool names to
  # resolve. Dated well before twm_por, so StandardPool.current is untouched.
  def pool_of_its_own(index)
    set = CardSet.create!(code: "Q#{index}", name: "Quiet Set #{index}", release_date: Date.new(2025, 1, 1))
    StandardPool.create!(
      first_card_set: card_sets(:twm), last_card_set: set, regulation_marks: %w[G H],
      released_on: Date.new(2025, 1, 1) + index, legal_on: Date.new(2025, 2, 1) + index
    )
  end
end
