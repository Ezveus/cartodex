require "test_helper"

# Pundit resolves a record's policy through Tournament.policy_class when the class defines it,
# which is how the test below refuses an action that carries no :id — the id-less policies
# (index?, mine?, create?) can only refuse a nil user, and Stage 1's `authenticate :user` block
# means no request ever reaches them with one.
class RefusingTournamentPolicy < TournamentPolicy
  def create? = false
end

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @tournament = tournaments(:one) # created_by: one
    @other_tournament = tournaments(:two) # created_by: two
    sign_in @user
  end

  test "index lists every event in the catalog, whoever catalogued it" do
    get tournaments_path

    assert_response :success
    assert_select ".data-table-row", count: 2
    assert_select ".data-table-row", text: /Local League Cup/
  end

  test "index marks the events the reader attended" do
    get tournaments_path

    assert_select ".data-table-row", text: /Regional Championship/ do
      assert_select ".tournament-attended", text: "You attended"
    end
    assert_select ".data-table-row", text: /Local League Cup/ do
      assert_select ".tournament-attended", count: 0
    end
  end

  test "index filters by name" do
    get tournaments_path(q: "local")

    assert_response :success
    assert_select ".data-table-row", count: 1
    assert_select ".data-table-row", text: /Local League Cup/
  end

  test "index ignores a blank q" do
    get tournaments_path(q: "   ")

    assert_select ".data-table-row", count: 2
  end

  test "index keeps the query in the search field" do
    get tournaments_path(q: "local")

    assert_select "form.tournaments-search input[name=q][value=local]"
  end

  # The filter form targets this frame so the field survives the debounce — see
  # Tournaments::IndexView::FRAME_ID.
  test "index wraps the results in the turbo frame the filter form targets" do
    get tournaments_path

    assert_select "turbo-frame#tournament_results .data-table-row"
    assert_select "form.tournaments-search[data-turbo-frame=tournament_results][data-turbo-action=replace]"
  end

  # The spotlight renders "See all N tournaments" from Search::Global; this page must show N.
  test "index shows exactly as many events as the spotlight's total promises" do
    get tournaments_path(q: "regional")

    assert_equal Search::Global.call(user: @user, query: "regional").tournament_total,
      css_select(".data-table-row").size
  end

  test "index paginates and its pager links replace the address bar" do
    (TournamentsController::CATALOG_PER_PAGE + 1).times do |i|
      Tournament.create!(name: "Filler Cup #{i}", date: Date.new(2026, 6, 1) + i,
                         tier: "league_cup", format: "expanded", created_by: @user)
    end

    get tournaments_path

    assert_select ".cards-pagination-info", text: %r{Page 1 / 2}
    assert_select "a.cards-pagination-link[data-turbo-action=replace]", text: /Next/
  end

  test "an unknown page number does not blow up" do
    get tournaments_path(page: [ "1" ])

    assert_response :success
  end

  # The Format column names the event's Standard pool, and StandardPool#name reads both of the
  # pool's card-set bounds — so an unpreloaded catalog costs three extra queries per Standard
  # event. Each event gets a pool of its own on purpose: events sharing a pool id issue
  # identical SQL, which the per-request query cache serves and count_queries does not count,
  # hiding the very N+1 this guards. Modelled on the same test in DecksControllerTest.
  test "index issues a constant number of queries regardless of how many events" do
    2.times { |i| catalog_event(i) }

    get tournaments_path # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get tournaments_path }

    (2..7).each { |i| catalog_event(i) }

    large = count_queries { get tournaments_path }

    assert_response :success
    assert_equal small, large, "query count grew with the catalog: #{small} -> #{large}"
  end

  test "show renders the event and offers the reader their own entry" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select "h1", text: @tournament.name
    assert_select "a[href=?]", tournament_entry_path(@tournament, tournament_entries(:one)), text: /Your entry/
  end

  # Entry uniqueness is per Play! Pokémon profile, not per user: a parent tracking their own and
  # their child's profiles has two participations in one event. A singular find_by picks one of
  # them arbitrarily and leaves the other unreachable from the page.
  test "show reaches every one of the reader's entries and tells them apart" do
    second = second_entry_for_misty

    get tournament_path(@tournament)

    assert_response :success
    assert_select "a[href=?]", tournament_entry_path(@tournament, tournament_entries(:one)), text: /Ash Ketchum/
    assert_select "a[href=?]", tournament_entry_path(@tournament, second), text: /Misty/
  end

  # With one participation there is nothing to tell apart, and naming the profile would be noise.
  test "show does not name the profile when the reader has a single entry" do
    get tournament_path(@tournament)

    assert_select "a[href=?]", tournament_entry_path(@tournament, tournament_entries(:one)), text: "Your entry"
  end

  # The other half of the same bug: once one profile was recorded, the page offered no way at
  # all to record the second — the "Record your participation" button was gone.
  test "show still offers to record a participation for a profile that has none here" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select "a[href=?]", new_tournament_entry_path(@tournament), text: /Record another/
  end

  test "show stops offering another participation once every profile is recorded" do
    second_entry_for_misty

    get tournament_path(@tournament)

    assert_response :success
    assert_select "a[href=?]", new_tournament_entry_path(@tournament), false
  end

  test "show invites a reader with no entry to record one" do
    get tournament_path(@other_tournament)

    assert_response :success
    assert_select "a[href=?]", new_tournament_entry_path(@other_tournament), text: /Record/
  end

  # rescue_from covers every action, and four of them carry no :id — the id-less policies can
  # only refuse a nil user today, which Stage 1's `authenticate :user` block already prevents,
  # so this is reached by refusing an id-less action on purpose. Stage 2 lifts that gate and
  # makes the same path a 500 (ActionController::UrlGenerationError) for any signed-out POST.
  test "a refusal on an action with no id lands on the catalog rather than raising" do
    Tournament.define_singleton_method(:policy_class) { RefusingTournamentPolicy }

    post tournaments_path, params: { tournament: {
      name: "Refused Cup", date: Date.current, tier: "league_cup", format: "expanded"
    } }

    assert_redirected_to tournaments_path
  ensure
    Tournament.singleton_class.send(:remove_method, :policy_class)
  end

  # An event page says nothing about anybody else — decision 4 of the spec.  # An event page says nothing about anybody else — decision 4 of the spec.
  test "show names no other member and no other deck" do
    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /#{decks(:two).name}/, count: 0
    refute_match users(:two).email, response.body
  end

  test "show 404s on an unknown event" do
    get tournament_path(id: 999_999)

    assert_response :not_found
  end

  test "a visitor sees the event and no control that would bounce them to sign in" do
    sign_out @user

    get tournament_path(@tournament)

    assert_response :success
    assert_select "h1", text: @tournament.name
    assert_select ".tournament-details", text: /#{@tournament.tier_label}/
    assert_select "a[href=?]", new_tournament_entry_path(@tournament), count: 0
    assert_select "a[href=?]", edit_tournament_path(@tournament), count: 0
  end

  test "a visitor's catalog offers no way to add a tournament" do
    sign_out @user

    get tournaments_path

    assert_response :success
    assert_select ".data-table-row", count: 2
    assert_select "a[href=?]", new_tournament_path, count: 0
    assert_select ".tournament-attended", count: 0
  end

  test "mine lists the reader's own participations only" do
    get mine_tournaments_path

    assert_response :success
    assert_select ".data-table-row", count: 1
    assert_select ".data-table-row", text: /Regional Championship/
  end

  test "new renders the event form and nothing about a deck" do
    get new_tournament_path

    assert_response :success
    assert_select "form input[name='tournament[name]']"
    assert_select "form select[name='tournament[deck_id]']", count: 0
  end

  test "create saves the event, records the creator, and moves on to the participation" do
    assert_difference -> { Tournament.count }, 1 do
      post tournaments_path, params: {
        tournament: {
          name: "City Championship", date: "2026-05-01", tier: "league_cup",
          format: "standard", standard_pool_id: standard_pools(:twm_por).id
        }
      }
    end

    created = Tournament.order(:id).last
    assert_equal @user, created.created_by
    assert_redirected_to new_tournament_entry_path(created)
  end

  test "create with invalid params re-renders the form" do
    assert_no_difference -> { Tournament.count } do
      post tournaments_path, params: { tournament: { name: "", date: "2026-05-01" } }
    end

    assert_response :unprocessable_entity
  end

  # Half the anti-duplicate mechanism: being blocked is useless without being told where to go.
  test "create on a duplicate names the existing event and links to it" do
    assert_no_difference -> { Tournament.count } do
      post tournaments_path, params: {
        tournament: {
          name: @tournament.name.upcase, date: @tournament.date.to_s, tier: "regional",
          format: "standard", standard_pool_id: standard_pools(:twm_por).id
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "a[href=?]", tournament_path(@tournament), text: /#{@tournament.name}/
  end

  test "the creator updates the event" do
    patch tournament_path(@tournament), params: { tournament: { name: "Renamed" } }

    assert_redirected_to tournament_path(@tournament)
    assert_equal "Renamed", @tournament.reload.name
  end

  # 404 is the deck rule and it is deliberately not this one: an event's existence is public,
  # so the honest answer is "not yours", with somewhere to go.
  test "another member is sent back to the event with an alert instead of a 404" do
    patch tournament_path(@other_tournament), params: { tournament: { name: "Hacked" } }

    assert_redirected_to tournament_path(@other_tournament)
    assert_not_equal "Hacked", @other_tournament.reload.name
  end

  test "an admin updates anybody's event" do
    @user.update!(admin: true)

    patch tournament_path(@other_tournament), params: { tournament: { name: "Moderated" } }

    assert_redirected_to tournament_path(@other_tournament)
    assert_equal "Moderated", @other_tournament.reload.name
  end

  test "destroy is refused while participations remain, with a flash that counts them" do
    assert_no_difference -> { Tournament.count } do
      delete tournament_path(@tournament)
    end

    assert_redirected_to tournament_path(@tournament)
    assert_match(/2 participations/, flash[:alert])
  end

  test "destroy succeeds once nothing points at the event" do
    @tournament.entries.destroy_all

    assert_difference -> { Tournament.count }, -1 do
      delete tournament_path(@tournament)
    end

    assert_redirected_to tournaments_path
  end

  # The pool notice tests below are the ones the old suite carried; they move with the form and
  # keep their reasoning. For a tournament the comparison is the pool legal on its date, not
  # the newest one: a March 2026 event anchored to the latest pool is a data-entry error.
  test "editing an event whose anchor disagrees with its date says so" do
    @tournament.update!(date: Date.new(2026, 1, 20), standard_pool: standard_pools(:twm_por))

    get edit_tournament_path(@tournament)

    assert_response :success
    assert_select ".standard-pool-notice", text: /TWM-ASC/
  end

  test "an event correctly anchored for its date is not nagged" do
    @tournament.update!(date: Date.new(2026, 3, 14), standard_pool: standard_pools(:twm_por))

    get edit_tournament_path(@tournament)

    assert_select ".standard-pool-notice", count: 0
  end

  test "an event dated before any tracked pool is not nagged despite carrying an anchor" do
    @tournament.update!(date: Date.new(2020, 1, 1), standard_pool: standard_pools(:twm_por))

    get edit_tournament_path(@tournament)

    assert_select ".standard-pool-notice", count: 0
  end

  test "an event anchored to an older pool than its date calls for is nagged" do
    @tournament.update!(date: Date.new(2026, 2, 1), standard_pool: standard_pools(:twm_asc))

    get edit_tournament_path(@tournament)

    assert_select ".standard-pool-notice", text: /TWM-POR/
    assert_select ".standard-pool-notice", text: /released since/
    # Guards the regression that shipped once and was caught by a human: this branch's copy
    # used to read "update it if you still play this deck" on a page with no deck on it.
    assert_select ".standard-pool-notice", text: /update the anchor/
    notice = css_select(".standard-pool-notice").first.text
    refute_match(/deck/i, notice, "the notice must not name a record type: it renders for tournaments too")
  end

  test "a rejected update that blanked the date is not nagged about the anchor" do
    @tournament.update!(date: Date.new(2026, 2, 1), standard_pool: standard_pools(:twm_asc))

    patch tournament_path(@tournament), params: { tournament: { date: "" } }

    assert_response :unprocessable_entity
    assert_select ".standard-pool-notice", count: 0
  end

  private

  # users(:one) owns two Play! Pokémon profiles; tournament_entries(:one) already spends `ash`
  # on @tournament, so this is the second player they are legitimately tracking there.
  def second_entry_for_misty
    deck = Deck.create!(user: @user, name: "Second Player Deck", standard_pool: standard_pools(:twm_por))
    @user.tournament_entries.create!(
      tournament: @tournament, deck: deck, tournament_profile: tournament_profiles(:misty)
    )
  end

  # A Standard event anchored to a pool nothing else uses, so the Format column really does
  # have to read that pool's two bounds.
  def catalog_event(index)
    Tournament.create!(
      name: "Quiet Cup #{index}", date: Date.new(2026, 7, 1) + index, tier: "league_cup",
      format: "standard", standard_pool: pool_of_its_own(index), created_by: @user
    )
  end

  # Copied from DecksControllerTest, where the same flat-cost test needs the same thing.
  def pool_of_its_own(index)
    set = CardSet.create!(code: "T#{index}", name: "Quiet Set #{index}", release_date: Date.new(2025, 1, 1))
    StandardPool.create!(
      first_card_set: card_sets(:twm), last_card_set: set, regulation_marks: %w[G H],
      released_on: Date.new(2025, 1, 1) + index, legal_on: Date.new(2025, 2, 1) + index
    )
  end
end
