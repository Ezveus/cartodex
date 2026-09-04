require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Original", description: "Desc")
    sign_in @user
  end

  test "a signed-in stranger sees a shared deck's decklist and none of its owner controls" do
    honedge = cards(:honedge)
    @deck.update!(shared: true, physical: true)
    # A real owned copy, so the owner's view would carry `.deck-card-alloc` — otherwise that
    # absence assertion passes on every deck, physical or not, and proves nothing.
    @user.collections.find_or_create_by!(card: honedge).update!(quantity: 1)
    @deck.deck_cards.find_by!(card: honedge).update!(owned_copies: 1)

    # A second printing of Honedge, so Cards::Printings.swappable_card_ids includes it and the
    # owner's row would carry `.deck-card-set-swap` — otherwise that absence assertion is equally
    # vacuous. A real Card record: fixtures bypass compute_fingerprint, so the fixture's literal
    # fingerprint has to be forced onto a genuinely created row afterward, same as
    # Cards::PrintingsTest's `reprint` helper.
    honedge_reprint = Card.create!(
      name: honedge.name, card_type: "Pokémon", hp: honedge.hp, type_symbol: honedge.type_symbol,
      retreat_cost: honedge.retreat_cost, stage: honedge.stage,
      card_set: card_sets(:asc), set_name: "ASC", set_number: "99", rarity: "Common"
    )
    honedge_reprint.update_column(:fingerprint, honedge.fingerprint)

    # Fixtures carry no image_url, so data-card-preview-url would otherwise be nil on every row
    # (Phlex omits a nil data attribute) and the DOM-contract assertion below would prove nothing.
    cards(:doublade).update!(image_url: "https://example.test/doublade.png")
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2, owned_copies: 0)
    sign_in users(:two)

    get deck_path(@deck)

    assert_response :success
    assert_select "h1", text: @deck.name
    assert_select ".deck-card-item", count: 2

    # The DOM contract the image export depends on — the export is public, so these are
    # requirements, not incidental markup.
    assert_select ".deck-show-header h1"
    assert_select ".deck-card-item[data-card-preview-url]"
    assert_select ".deck-card-item .deck-card-qty"

    # Absence assertions: the whole point of a separate view is that it cannot render these.
    # Setup above makes each one non-vacuous — the deck is physical with an owned copy, and
    # honedge has a second printing — so Decks::ShowView would render every one of them for
    # the owner (see "the owner still sees ..." below), and the public view still must not.
    assert_select ".deck-card-alloc", count: 0
    assert_select ".deck-card-set-swap", count: 0
    assert_select ".deck-badges .badge", text: "Proxies", count: 0
    assert_select "a[href=?]", edit_deck_path(@deck), count: 0
    assert_select "button", text: "Log Result", count: 0
    assert_select ".deck-card-search", count: 0
  end

  # What makes every absence assertion above meaningful: on the very same deck, the owner's
  # request does carry the allocation and printing-swap controls the stranger's must not.
  test "the owner still sees the allocation and swap controls on the same deck" do
    honedge = cards(:honedge)
    @deck.update!(shared: true, physical: true)
    @user.collections.find_or_create_by!(card: honedge).update!(quantity: 1)
    @deck.deck_cards.find_by!(card: honedge).update!(owned_copies: 1)

    honedge_reprint = Card.create!(
      name: honedge.name, card_type: "Pokémon", hp: honedge.hp, type_symbol: honedge.type_symbol,
      retreat_cost: honedge.retreat_cost, stage: honedge.stage,
      card_set: card_sets(:asc), set_name: "ASC", set_number: "99", rarity: "Common"
    )
    honedge_reprint.update_column(:fingerprint, honedge.fingerprint)

    get deck_path(@deck)

    assert_response :success
    assert_select ".deck-card-alloc"
    assert_select ".deck-card-set-swap"
  end

  test "a signed-in stranger cannot see an unshared deck" do
    sign_in users(:two)

    get deck_path(@deck)

    assert_response :not_found
  end

  test "a stranger may export a shared deck but not its tournament pdf" do
    @deck.update!(shared: true)
    sign_in users(:two)

    get export_deck_path(@deck)
    assert_response :success

    get export_deck_path(@deck, style: "tournament_pdf", profile_id: 1)
    assert_response :not_found
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
    @deck.tournament_entries.destroy_all

    assert_difference -> { Deck.count }, -1 do
      delete deck_path(@deck)
    end

    assert_redirected_to decks_path
  end

  # Deck#tournament_entries is restrict_with_error, so #destroy answers false rather than
  # raising — and an action that redirected with "Deck deleted." either way would report a
  # deletion that did not happen.
  test "destroy refuses while a participation records the deck and says how many" do
    assert_predicate @deck.tournament_entries, :any?, "sanity: the fixture deck was played at an event"

    assert_no_difference -> { Deck.count } do
      delete deck_path(@deck)
    end

    assert_redirected_to deck_path(@deck)
    assert_match(/1 tournament participation/, flash[:alert])
  end

  test "destroy cascades to deck_cards and deck_results" do
    @deck.tournament_entries.destroy_all
    @deck.deck_cards.destroy_all
    @deck.deck_results.destroy_all
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
    @deck.deck_results.create!(result: "win", played_at: Time.current)

    assert_difference [ -> { DeckCard.count }, -> { DeckResult.count } ], -1 do
      delete deck_path(@deck)
    end
  end

  # Entry uniqueness is per Play! Pokémon profile, so one deck can carry two participations in
  # one event — and "Name (date)" prints the same string for both, leaving a select whose two
  # options a user cannot tell apart.
  test "the result modal tells two participations in one event apart" do
    second = @user.tournament_entries.create!(
      tournament: tournaments(:one), deck: @deck, tournament_profile: tournament_profiles(:misty)
    )

    get deck_path(@deck)

    assert_response :success
    assert_select "option[value=?]", tournament_entries(:one).id.to_s, text: /Ash Ketchum/
    assert_select "option[value=?]", second.id.to_s, text: /Misty/
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

    # The archetype form only renders in edit mode (Decks::HeaderFrame#edit_form).
    get edit_deck_path(@deck)

    assert_response :success
    assert_select "[data-archetype-picker-deck-key-value=?]", @deck.key
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

  # The result modal's tournament picker prints TournamentEntry#picker_label, which reads the
  # event *and* the Play! Pokémon profile — so the page has to preload both. Each participation
  # gets an event and a profile of its own on purpose: rows sharing an id issue identical SQL,
  # which the per-request query cache serves and count_queries does not count.
  test "show issues a constant number of queries regardless of how many participations" do
    get deck_path(@deck) # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get deck_path(@deck) }

    3.times { |i| participation_of_its_own(@deck, i) }

    large = count_queries { get deck_path(@deck) }

    assert_response :success
    assert_equal small, large, "query count grew with the participation count: #{small} -> #{large}"
  end

  # The format badge names the deck's Standard pool, and StandardPool#name reads both of  # The format badge names the deck's Standard pool, and StandardPool#name reads both of
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

  test "the shared index lists other people's shared decks to a visitor" do
    sign_out @user # this file's setup signs in; a visitor is the point here
    theirs = decks(:two)
    theirs.update!(user: users(:two), shared: true, name: "Theirs")

    get shared_decks_path

    assert_response :success
    assert_select ".deck-item-link h2", text: "Theirs"
    assert_select "a[href=?]", deck_path(@deck), count: 0
    # Same live-filter wiring as Decks::IndexView#search_input: without the debounce action,
    # typing here does nothing until Enter, unlike the sibling page this one is meant to match.
    assert_select "input[name=q][data-action=?]", "input->card-filter#debounce"
  end

  test "the shared index shows no collection-derived filter and nothing owner-only on a row" do
    theirs = decks(:two)
    theirs.update!(user: users(:two), shared: true, physical: true)
    theirs.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 0)
    # Five decided results at 100% is what makes `hot?` true — and the foil flag it renders is
    # the win rate, i.e. the record decision 3 keeps private.
    5.times { theirs.deck_results.create!(result: "win") }

    get shared_decks_path

    assert_response :success
    assert_select "select[name=proxies]", count: 0
    assert_select "select[name=support]", count: 0
    assert_select ".deck-badges .badge", text: "Proxies", count: 0
    assert_select ".deck-badges .badge", text: "Physical", count: 0
    assert_select ".deck-item-actions", count: 0
    assert_select ".deck-hot-flag", count: 0
    assert_select ".deck-item.is-foil", count: 0
    # No deck-compare controller on this page, so a checkbox here would be a live control that
    # does nothing.
    assert_select ".deck-compare-checkbox", count: 0
  end

  test "the shared index's archetype filter comes from the shared decks, not from mine" do
    theirs = decks(:two)
    # Fixtures are `ogerpon` and `budew_ogerpon` (test/fixtures/archetypes.yml); there is no :one.
    theirs.update!(user: users(:two), shared: true, archetype: archetypes(:ogerpon))

    get shared_decks_path

    assert_response :success
    assert_select "select[name=primary] option[value=?]", archetypes(:ogerpon).primary_card_id.to_s
  end

  test "a filter keystroke on the shared index asks for the grid alone" do
    sign_out @user
    theirs = decks(:two)
    theirs.update!(user: users(:two), shared: true, archetype: archetypes(:ogerpon), name: "Theirs")

    sql = capture_queries do
      get shared_decks_path, headers: { "Turbo-Frame" => Decks::SharedIndexView::FRAME_ID }
    end

    assert_response :success
    assert_select "turbo-frame[id=?] .decks-grid .deck-item", Decks::SharedIndexView::FRAME_ID
    # The filter bar sits outside the frame, so Turbo throws it away — which means the query
    # that fills its archetype select should not have run. Same short-circuit as
    # DecksController#index, on the endpoint a debounced field fires per keystroke.
    assert_select "select[name=primary]", count: 0
    assert_empty sql.grep(/"archetypes"\."primary_card_id" FROM "archetypes"/),
      "expected the archetype filter options not to be built for a frame request"
  end

  test "the shared index loads its page of decks once" do
    sign_out @user
    decks(:two).update!(user: users(:two), shared: true)

    sql = capture_queries { get shared_decks_path }

    assert_response :success
    # `any?` on an unloaded relation is a SELECT 1 … LIMIT 1 beside the page query that
    # immediately follows it.
    assert_empty sql.grep(/SELECT 1 AS one/),
      "expected no existence probe beside the page query"
  end

  test "sharing a deck flips the flag and re-renders the modal with the link" do
    patch share_deck_path(@deck), params: { shared: "1" }, as: :turbo_stream

    assert_response :success
    assert_predicate @deck.reload, :shared?
    assert_match deck_url(@deck), response.body
  end

  test "unsharing takes the deck off the shared index without changing its key" do
    @deck.update!(shared: true)
    key = @deck.key

    patch share_deck_path(@deck), params: { shared: "0" }, as: :turbo_stream

    assert_response :success
    refute_predicate @deck.reload, :shared?
    assert_equal key, @deck.key
  end

  test "unsharing with the parameter missing altogether still unshares" do
    # What a bare check_box_tag posts when unchecked: nothing. Without the hidden "0" field
    # (and the `|| false` behind it) this is update!(shared: nil) against a NOT NULL column.
    @deck.update!(shared: true)

    patch share_deck_path(@deck), params: {}, as: :turbo_stream

    assert_response :success
    refute_predicate @deck.reload, :shared?
  end

  test "the share response re-renders the frame, not a second dialog" do
    patch share_deck_path(@deck), params: { shared: "1" }, as: :turbo_stream

    assert_response :success
    # A dialog inside the stream would nest a closed <dialog> into the open one and blank it.
    assert_select "turbo-stream[action=replace][target=?]", Decks::ShareFrame::FRAME_ID
    assert_select "turbo-stream dialog", count: 0
    assert_select "turbo-stream turbo-frame[id=?]", Decks::ShareFrame::FRAME_ID
  end

  test "a stranger cannot share somebody else's deck" do
    sign_in users(:two)

    patch share_deck_path(@deck), params: { shared: "1" }, as: :turbo_stream

    assert_response :not_found
    refute_predicate @deck.reload, :shared?
  end

  test "the Shared badge appears on the owner's page only once the deck is shared" do
    @deck.update!(shared: true)

    get deck_path(@deck)

    assert_response :success
    assert_select ".deck-badges .badge", text: "Shared"

    @deck.update!(shared: false)

    get deck_path(@deck)

    assert_response :success
    assert_select ".deck-badges .badge", text: "Shared", count: 0
  end

  test "the export menu offers the owner the tournament PDF and a visitor everything else" do
    @deck.update!(shared: true)

    get deck_path(@deck)

    assert_response :success
    assert_select ".dropdown-item", text: "Copy for TCG Live"
    assert_select ".dropdown-item", text: "Copy as Cardmarket wishlist"
    assert_select ".dropdown-item", text: "Copy as image"
    assert_select ".dropdown-item", text: "Download as image"
    assert_select ".dropdown-item", text: "Download as tournament PDF"
    # The clipboard items carry the URL they copy; a missing value is a button that silently
    # copies nothing.
    assert_select ".dropdown-item[data-clipboard-url-value=?]", export_deck_path(@deck)
    assert_select ".dropdown-item[data-clipboard-url-value=?]", export_deck_path(@deck, style: "cardmarket")

    sign_out @user
    get deck_path(@deck)

    assert_response :success
    assert_select ".dropdown-item", text: "Copy for TCG Live"
    assert_select ".dropdown-item", text: "Download as image"
    # The one item the public page must not carry: tournament_pdf? is owner-only because it
    # reads one of the owner's profiles, so offering it here would be a button that 404s.
    assert_select ".dropdown-item", text: "Download as tournament PDF", count: 0
  end

  test "the shared index lays out its rows and pager with classes the stylesheet defines" do
    sign_out @user
    # One more than SHARED_PER_PAGE, so the pager renders at all.
    (DecksController::SHARED_PER_PAGE + 1).times do |i|
      Deck.create!(user: users(:two), name: "Shared #{i}", shared: true, standard_pool: standard_pools(:twm_por))
    end

    get shared_decks_path

    assert_response :success
    # application.css is the app's only stylesheet, and it has no rule for `.deck-list`,
    # `.pagination` or `.pagination-position`. A class it does not define is a page with no
    # layout, which no assertion about content can see.
    assert_select "div.decks-grid .deck-item"
    assert_select "div.deck-list", count: 0
    assert_select ".cards-pagination .cards-pagination-info"
    assert_select "nav.pagination", count: 0
    # Rows, pager and empty state inside the frame; the filter bar outside it.
    assert_select "turbo-frame[id=?] .decks-grid", Decks::SharedIndexView::FRAME_ID
    assert_select "turbo-frame[id=?] .cards-pagination", Decks::SharedIndexView::FRAME_ID
    assert_select "turbo-frame[id=?] form.deck-filters", Decks::SharedIndexView::FRAME_ID, count: 0
    # A pager link inside a frame navigates the frame and leaves the address bar behind
    # without this; a deck row escapes the frame through DeckCard's own _top.
    assert_select ".cards-pagination-link[data-turbo-action=?]", "replace"
    assert_select ".deck-item-link[data-turbo-frame=?]", "_top"
  end

  test "the shared index's empty state uses a class the stylesheet defines" do
    sign_out @user
    Deck.update_all(shared: false)

    get shared_decks_path

    assert_response :success
    assert_select "p.empty-state", text: "No shared decks yet."
    assert_includes File.read(Rails.root.join("app/assets/stylesheets/application.css")), ".empty-state"
  end

  test "the shared index survives a page parameter that is not a number" do
    sign_out @user

    # PubliclyReachable rescues RecordNotFound and NotAuthorizedError, nothing else, so a
    # NoMethodError here is an unhandled 500 on an endpoint any crawler can reach.
    get shared_decks_path(page: { a: "b" })
    assert_response :success

    get shared_decks_path, params: { page: [ "1" ] }
    assert_response :success
  end

  test "sharing works on a Standard deck that predates the pool anchor" do
    # A pre-backfill row, or any environment that skipped standard_pools:backfill_anchors:
    # the column is there, `validates :standard_pool, presence:, if: :standard?` is there,
    # and nothing has filled it in. An `update!` would rejoin that validation and leave the
    # deck neither shareable nor unshareable.
    @deck.update_column(:standard_pool_id, nil)

    patch share_deck_path(@deck), params: { shared: "1" }, as: :turbo_stream

    assert_response :success
    assert_predicate @deck.reload, :shared?
  end

  test "a client that does not speak turbo_stream is sent to the deck, not to a missing template" do
    # share has only a .turbo_stream.erb behind it. Without a format branch an
    # `Accept: text/html` request raises MissingTemplate *after* the flag has committed:
    # the write lands and the response is a 500.
    patch share_deck_path(@deck), params: { shared: "1" }

    assert_redirected_to deck_path(@deck)
    assert_predicate @deck.reload, :shared?
  end

  test "a visitor who opens a shared deck is returned to it after signing in" do
    sign_out @user
    @deck.update!(shared: true)

    get deck_path(@deck)

    assert_response :success
    assert_equal deck_path(@deck), session["user_return_to"]
  end

  test "a prefetch of a shared deck does not hijack where sign-in returns to" do
    sign_out @user
    @deck.update!(shared: true)

    # Turbo 8 prefetches on hover by default and marks the request with this header. Without
    # the guard, hovering a link rewrites user_return_to for a page nobody opened.
    get deck_path(@deck), headers: { "X-Sec-Purpose" => "prefetch" }

    assert_response :success
    assert_nil session["user_return_to"]
  end

  test "a member reading someone else's shared deck keeps their own return-to" do
    theirs = decks(:two)
    theirs.update!(user: users(:two), shared: true)

    get deck_path(theirs)

    assert_response :success
    assert_nil session["user_return_to"]
  end

  # `@deck.user_id == current_user&.id` was true with both sides nil, so an ownerless field list
  # served the owner's page — inline editing, allocation steppers and all — to the public.
  test "a visitor on an ownerless shared deck gets the public page, not the owner's" do
    sign_out @user

    get deck_path(decks(:field_list))

    assert_response :success
    assert_select ".deck-card-item"
    assert_select "form.deck-form", count: 0
    assert_select ".deck-actions-dropdown", count: 0
  end

  private

  # A pool nothing else shares, so that a page rendering N decks has N pool names to
  # resolve. Dated well before twm_por, so StandardPool.current is untouched.
  # One participation, in an event and under a profile nothing else shares — see the flat-cost
  # test above for why sharing either would hide the N+1 it guards.
  def participation_of_its_own(deck, index)
    event = Tournament.create!(
      name: "Quiet Open #{index}", date: Date.new(2026, 5, 1) + index,
      tier: "league_cup", format: "expanded", created_by: @user
    )
    profile = @user.tournament_profiles.create!(
      player_name: "Player #{index}", player_id: "200000#{index}", date_of_birth: Date.new(2000, 1, 1)
    )
    @user.tournament_entries.create!(tournament: event, deck: deck, tournament_profile: profile)
  end

  def pool_of_its_own(index)
    set = CardSet.create!(code: "Q#{index}", name: "Quiet Set #{index}", release_date: Date.new(2025, 1, 1))
    StandardPool.create!(
      first_card_set: card_sets(:twm), last_card_set: set, regulation_marks: %w[G H],
      released_on: Date.new(2025, 1, 1) + index, legal_on: Date.new(2025, 2, 1) + index
    )
  end
end

# The picker was soldered to a deck: it read @deck.key for the Suggest button and
# @deck.archetype&.name for the input's value. A standings row has an archetype and no deck, and
# a degraded copy of this picker was the alternative to extracting it.
class DecksControllerArchetypePickerTest < ActionDispatch::IntegrationTest
  test "the archetype picker renders without a deck, minus the Suggest button" do
    # Rendered through a form for a record that is not a Deck, which is the whole point.
    html = ApplicationController.render(
      inline: <<~ERB,
        <%= form_with(model: TournamentStanding.new, url: "/nowhere") do |f| %>
          <%= render Ui::ArchetypePicker.new(form: f) %>
        <% end %>
      ERB
      layout: false
    )

    assert_includes html, "data-controller=\"archetype-picker\""
    assert_includes html, "archetype-picker-target=\"input\""
    refute_includes html, ">Suggest<"
    # Never a stale deck key: the Suggest handler is the only reader, and it must see nothing.
    refute_includes html, "archetype-picker-deck-key-value"
  end

  test "the archetype picker keeps its Suggest button when given a deck key" do
    html = ApplicationController.render(
      inline: <<~ERB,
        <%= form_with(model: Deck.new, url: "/nowhere") do |f| %>
          <%= render Ui::ArchetypePicker.new(form: f, deck_key: "abc123") %>
        <% end %>
      ERB
      layout: false
    )

    assert_includes html, ">Suggest<"
    assert_includes html, "archetype-picker-deck-key-value=\"abc123\""
  end
end
