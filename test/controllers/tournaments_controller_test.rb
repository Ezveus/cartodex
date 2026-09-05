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

  # An event page says nothing about anybody else — decision 4 of the spec.
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

  # The same assertion for the reader who *has* a session but did not catalogue the event. It
  # is a different gate — policy(@tournament).edit? rather than the absence of a user — and
  # only the visitor half was pinned.
  test "a signed-in stranger sees no way to change an event they did not catalogue" do
    sign_in users(:two)

    get tournament_path(@tournament)

    assert_response :success
    assert_select "h1", text: @tournament.name
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

  # The other half of that: attended_ids is commented "none at all for a visitor", and the
  # markup assertion above cannot see the difference between returning early and querying
  # anyway. This is the one that can — a variant which runs the grouped query for a visitor
  # renders exactly the same page.
  test "a visitor's catalog never queries the participations" do
    sign_out @user

    sql = capture_queries { get tournaments_path }

    assert_response :success
    assert_empty sql.grep(/tournament_entries/i)
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

  # F1: the three division field sizes used to be permitted by nothing and rendered by no form,
  # so TournamentStanding#placement_within_division_field could never see one. This reads the
  # field names off the *rendered* edit form rather than assuming the attribute names, the same
  # idiom "the decklist field's rendered name is what the controller reads"
  # (standings_controller_test.rb) uses for the reason named there: a hand-built params hash
  # would pass even if the fields silently rendered under the wrong name.
  #
  # open_participant_count joined them for the online import, and it is the one of the four
  # anything ever writes on its own — so it is the one a wrong value really strands: it caps a
  # placement through TournamentStanding#placement_within_division_field, and with no input here
  # every standing above it would be unsavable through the wiki form with nowhere in the app to
  # correct the number.
  test "the four division field sizes round-trip through the rendered form" do
    get edit_tournament_path(@tournament)
    assert_response :success

    values = {
      "junior_participant_count" => 32,
      "senior_participant_count" => 64,
      "masters_participant_count" => 128,
      "open_participant_count" => 259
    }
    params = values.each_with_object({}) do |(attr, value), memo|
      field = css_select("input[name='tournament[#{attr}]']").first
      assert_not_nil field, "the form must render a #{attr} field"
      memo[field["name"]] = value
    end

    patch tournament_path(@tournament), params: params

    assert_redirected_to tournament_path(@tournament)
    @tournament.reload
    assert_equal 32, @tournament.junior_participant_count
    assert_equal 64, @tournament.senior_participant_count
    assert_equal 128, @tournament.masters_participant_count
    assert_equal 259, @tournament.open_participant_count
  end

  test "a negative open field size is refused" do
    patch tournament_path(@tournament), params: {
      tournament: { open_participant_count: -3 }
    }

    assert_response :unprocessable_entity
    assert_nil @tournament.reload.open_participant_count
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

  # Entries cleared first, same as the success case above: restrict_with_error would save the
  # row on its own with the entry still attached, and that is not what this test is proving.
  # It is authorization, not the dependency guard, that must keep a stranger from deleting it.
  test "another member cannot delete the event" do
    @other_tournament.entries.destroy_all

    assert_no_difference -> { Tournament.count } do
      delete tournament_path(@other_tournament)
    end

    assert_redirected_to tournament_path(@other_tournament)
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

  test "show renders the event's standings, grouped by division and ranked" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select "h3", text: "Masters"
    assert_select ".data-table-row", text: /Giovanni/
    assert_select ".data-table-row", text: /Ash Ketchum/
    # Ranked before unranked, and 7th before 33rd within the division.
    players = css_select(".tournament-standings .data-table-row").map(&:text)
    assert players.index { |row| row.include?("Giovanni") } <
           players.index { |row| row.include?("Ash Ketchum") },
      "expected the better placement first"
  end

  # This pins the *view's* half of the rule and only that: Standings::Table iterates DIVISIONS and
  # looks each up in group_by, so these headings come out in age order whatever SQL did — reverting
  # as_a_sheet to alphabetical leaves this test green (checked). The SQL half is pinned by "a page
  # boundary falls where the reader expects it", below, which is the only place the two can be told
  # apart. Junior and senior are added here (not to fixtures, to stay clear of the other tests and the
  # system-suite obligation a fixture change would carry); the existing masters fixtures are what
  # actually separates age order from alphabetical, since junior/senior sort the same way under
  # both rules.
  test "the sheet lists divisions in Play! Pokémon's age order, not alphabetical" do
    archetype = archetypes(:standings_marker)
    @tournament.standings.create!(player_name: "Junior Player", division: "junior", archetype: archetype)
    @tournament.standings.create!(player_name: "Senior Player", division: "senior", archetype: archetype)

    get tournament_path(@tournament)

    assert_equal %w[Junior Senior Masters], css_select(".tournament-standings > h3").map(&:text)
  end

  test "a standing's row names its archetype and its record" do
    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /Giovanni/ do
      assert_select ".badge", text: tournament_standings(:giovanni_masters).archetype.name
      assert_select ".data-table-cell", text: "7-2-0"
      assert_select ".data-table-cell", text: "#7"
    end
  end

  test "a standing with a field list links to it, and one without says so" do
    tournament_standings(:ash_masters).update!(deck: decks(:field_list))

    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /Ash Ketchum/ do
      assert_select "a[href=?]", deck_path(decks(:field_list)), text: "Decklist"
    end
    assert_select ".data-table-row", text: /Giovanni/ do
      assert_select "a", text: "Decklist", count: 0
    end
  end

  # A hand-typed sheet is a handful of rows and an imported one is a Worlds field. The page is
  # public and deliberately carries no rate limit ("one page load per click"), which was only ever
  # safe while nothing could make one click expensive.
  test "the sheet renders one page at a time" do
    fill_sheet(TournamentStanding::SHEET_PER_PAGE + 5)

    get tournament_path(@tournament)

    assert_equal TournamentStanding::SHEET_PER_PAGE, css_select(".tournament-standings .data-table-row").size
    assert_select ".cards-pagination-info", text: "Page 1 / 2"
  end

  test "the second page holds the rest of the sheet" do
    fill_sheet(TournamentStanding::SHEET_PER_PAGE + 5)
    first_page_players = page_players(1)

    players = page_players(2)

    assert_equal 7, players.size # 5 added + the two fixture rows, which sort last by placement
    assert_empty players & first_page_players
  end

  # The URL is public, so something will try `?page=99`. Running off the end renders an empty
  # table under "No standings recorded for this event yet.", which is false.
  test "a page past the end of the sheet shows the last page rather than an empty one" do
    fill_sheet(TournamentStanding::SHEET_PER_PAGE + 5)

    get tournament_path(@tournament, page: 99)

    assert_response :success
    assert_select ".cards-pagination-info", text: "Page 2 / 2"
    assert_select "p.empty-state", count: 0
  end

  # The catalog is public and paginated too, and its out-of-range page told the same lie the
  # sheet's did: "No tournaments catalogued yet." over a catalog that is not empty.
  test "a page past the end of the catalog shows the last page rather than an empty one" do
    get tournaments_path(page: 99)

    assert_response :success
    assert_select ".data-table-row", minimum: 1
    assert_select "p", text: "No tournaments catalogued yet.", count: 0
  end

  test "a sheet that fits on one page has no pager" do
    get tournament_path(@tournament)

    assert_select ".cards-pagination", count: 0
  end

  # The order the divisions are read in lives in SQL now, and this is why it had to move there:
  # `ORDER BY division` is alphabetical (junior, masters, senior) while players read junior,
  # senior, masters, so a page boundary drawn in SQL falls somewhere the reader never sees — page
  # two of a Worlds sheet opening in the middle of a division page one appeared to finish.
  #
  # Asserted on the rows and not on the headings, because the headings cannot see this: the table
  # regroups whatever it is handed into DIVISIONS order, so both rules print "Senior" above
  # "Masters" on whichever page their rows landed. Thirty of each, so the two orders disagree
  # about which side of the boundary the seniors fall on: read as players do they all fit on page
  # one, read alphabetically twelve of them are pushed onto page two behind the masters.
  test "a page boundary falls where the reader expects it, not where the alphabet does" do
    fill_sheet(30, division: "senior", prefix: "Senior")
    fill_sheet(30, division: "masters", prefix: "Master")

    page_one = page_players(1)
    page_two = page_players(2)

    assert_equal 30, rows_naming(page_one, "Senior"), "page one should hold every senior"
    assert_equal 0, rows_naming(page_two, "Senior"),
      "a senior was pushed onto page two, which is what the alphabetical order does"
  end

  test "an event with no standings says so with a class the stylesheet defines" do
    @tournament.standings.destroy_all

    get tournament_path(@tournament)

    assert_select "p.empty-state", text: "No standings recorded for this event yet."
  end

  test "the row of the reader's own linked participation is marked as theirs" do
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))

    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /Ash Ketchum/ do
      assert_select ".badge", text: "You"
    end
  end

  test "a visitor sees the sheet and no ownership marker on it" do
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))
    sign_out @user

    get tournament_path(@tournament)

    assert_response :success
    assert_select ".data-table-row", text: /Ash Ketchum/
    assert_select ".badge", text: "You", count: 0
  end

  # Distinct from the nil-viewer case above: this is a signed-in reader who simply isn't the
  # linked entry's owner. Row#mine? is `@viewer.present? && ...user_id == @viewer.id`, so a
  # stranger's presence alone must not trip the short-circuit — a safety property on a public
  # page worth pinning on its own rather than trusting to inspection.
  test "a signed-in stranger to the linked participation is not marked as its owner" do
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))
    sign_out @user
    sign_in users(:two)

    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /Ash Ketchum/ do
      assert_select ".badge", text: "You", count: 0
    end
  end

  # Ui::ArchetypeBadge reads the archetype's cards and the "You" marker reads the linked entry's
  # user_id, so both belong in the includes. Modelled on the four tests that already guard
  # with_standard_pool.
  test "show issues a constant number of queries regardless of how many standings" do
    2.times { |i| record_standing(i) }

    get tournament_path(@tournament) # warm the session

    small = count_queries { get tournament_path(@tournament) }

    (2..7).each { |i| record_standing(i) }

    large = count_queries { get tournament_path(@tournament) }

    assert_response :success
    assert_equal small, large, "query count grew with the sheet: #{small} -> #{large}"
  end

  test "the event page offers to publish each participation no standing names yet" do
    get tournament_path(@tournament)

    assert_select "a[href=?]",
      new_tournament_standing_path(@tournament, tournament_entry_id: tournament_entries(:one).id),
      text: "Publish my participation"
  end

  test "a published participation is no longer offered for publishing" do
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))

    get tournament_path(@tournament)

    assert_select "a[href*=?]", "tournament_entry_id=#{tournament_entries(:one).id}", count: 0
  end

  # Plural, for the reason my_entries is: entry uniqueness is per Play! Pokémon profile, so a
  # parent tracking two profiles has two participations here and both must be publishable.
  test "two unpublished participations are offered separately, named by their player" do
    second_entry_for_misty

    get tournament_path(@tournament)

    assert_select "a", text: /Publish Ash Ketchum's participation/
    assert_select "a", text: /Publish Misty's participation/
  end

  # F5: publish_label used to key on @my_entries.one? while it is @claimable_entries that
  # publish_actions actually iterates. With one of two entries already published, @my_entries
  # stays at two but @claimable_entries drops to one — the remaining button must read
  # unambiguously, since there is only one option left to choose from.
  test "a reader with two entries, one already published, gets an unambiguous label for the other" do
    second_entry_for_misty
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))

    get tournament_path(@tournament)

    assert_select "a", text: "Publish my participation"
    assert_select "a", text: /Publish Misty's participation/, count: 0
  end

  # An online event has no age divisions, so offering to attach a Play! Pokémon profile to one is
  # wrong on its face — and it is not cosmetic: `Tournament has_many :entries, dependent:
  # :restrict_with_error`, so one member accepting makes an imported event permanently
  # undeletable. Withheld, not refused: nothing here stops a member who reaches the route anyway,
  # the page simply stops proposing it.
  test "an online event's page proposes neither a participation nor a claim" do
    event, standing = online_event_with_unclaimed_row

    get tournament_path(event)

    assert_response :success
    assert_select ".data-table-row", text: /#{standing.player_name}/ # the sheet still renders
    assert_select "a[href=?]", new_tournament_entry_path(event), count: 0
    assert_select "button", text: /This is me/, count: 0
  end

  # The other half of decision §3, and the half nothing else asserts: an online event is
  # catalogued because a standing needs a Tournament, not because anybody went to it. One
  # archetype's leaderboard is 20 of them and the online index lists 139 archetypes, so left in
  # the catalog they bury the handful of events members actually attend. #show stays reachable —
  # an event's existence is not a secret, and hiding it would be a new rule.
  #
  # The paper assertion is the negative control: without it this passes when the catalog is empty
  # for every event.
  test "the catalog lists a paper event and never an imported online one, which still has a page" do
    event, = online_event_with_unclaimed_row

    get tournaments_path

    assert_response :success
    assert_select ".data-table-row a", text: @tournament.name, minimum: 1
    assert_select ".data-table-row a", text: event.name, count: 0

    get tournament_path(event)
    assert_response :success
  end

  # The three withheld invitations and the "Back to Tournaments" link to a catalog that does not
  # contain this event are four absences with one cause, and until the page named it they read as
  # four bugs. EventDetails prints the venue beside the date, tier and format — the facts, where a
  # fact about the event belongs, and on both pages that print them.
  test "an online event's page names its venue and says what follows from it" do
    event, = online_event_with_unclaimed_row

    get tournament_path(event)

    assert_response :success
    assert_select ".tournament-details .data-table-row", text: /Venue/ do
      assert_select ".data-table-cell", text: /Online play/
      assert_select ".data-table-cell", text: /not in the tournament catalog/
    end
  end

  # The negative control, and it has to be worded on the row rather than on the word "Online":
  # a paper event's Format cell legitimately reads whatever other_format_name holds.
  test "a paper event's page names no venue" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select ".tournament-details .data-table-row", text: /Venue/, count: 0
  end

  # The negative control. Without it the test above passes just as happily when the whole entry
  # section has been broken for every event, online or not.
  test "a paper event's page proposes both" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select "a[href=?]", new_tournament_entry_path(@tournament), text: /Record another/
    assert_select "button", text: /This is me/, minimum: 1
  end

  test "a visitor is offered nothing to publish" do
    sign_out @user

    get tournament_path(@tournament)

    assert_response :success
    assert_select "a", text: /Publish/, count: 0
  end

  private

  # What the online import writes, plus the two things that make the withholding visible: a
  # participation of the reader's own (so the header would otherwise offer to record another) and
  # an unclaimed row (so the sheet would otherwise offer "This is me"). Recording that entry is
  # exactly what the page must stop proposing — reaching the route anyway is not refused, which
  # is why a test can set one up at all. Built here rather than as a fixture because
  # public_access_test.rb asserts hard record counts.
  def online_event_with_unclaimed_row
    event = Tournament.create!(
      name: "Pumpkaweekly #12", date: Date.new(2026, 4, 18), tier: "other",
      format: "other", other_format_name: "Standard (Online)", online: true,
      open_participant_count: 259
    )
    deck = Deck.create!(user: @user, name: "Online Deck", standard_pool: standard_pools(:twm_por))
    @user.tournament_entries.create!(tournament: event, deck: deck)
    standing = event.standings.create!(
      player_name: "JRobrueda", division: "open", placement: 2,
      wins: 8, losses: 0, ties: 0, archetype: archetypes(:standings_marker)
    )
    [ event, standing ]
  end

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

  # An archetype of its own per row, so two rows never issue identical SQL that the per-request
  # query cache would serve — which is what hides an N+1 from count_queries. Likewise a
  # TournamentEntry of its own per row, linked via tournament_entry:, so the :tournament_entry
  # preload the controller takes is actually exercised: a nil FK never issues a query at all
  # (belongs_to short-circuits it), which is what let a first version of this helper leave that
  # preload's N+1 undetected — see the coordinator's fix-round-1 note.
  #
  # Correction to the brief: its version of this helper omits type_symbol/retreat_cost, which
  # Card requires for card_type: "Pokémon" and raises RecordInvalid without.
  # Deliberately lighter than record_standing: these tests care about how many rows a page holds,
  # not about what is in them, and record_standing builds a card, an archetype, a user and a deck
  # for every single row.
  def fill_sheet(count, division: "masters", prefix: "Player")
    count.times do |i|
      @tournament.standings.create!(
        player_name: "#{prefix} #{i}", division: division, placement: i + 1,
        archetype: archetypes(:standings_marker)
      )
    end
  end

  def rows_naming(players, prefix) = players.count { |row| row.include?(prefix) }

  def page_players(page)
    get tournament_path(@tournament, page: page)
    css_select(".tournament-standings .data-table-row").map(&:text)
  end

  def record_standing(index)
    card = Card.create!(
      name: "Quiet Pokémon #{index}", set_name: "QS#{index}", set_number: "1",
      card_type: "Pokémon", hp: 60, rarity: "Common", type_symbol: "Colorless", retreat_cost: 1
    )
    archetype = Archetype.create!(primary_card: card, name: "Quiet #{index}", custom_name: "1")
    # A User (and Deck) of its own per row: deck_belongs_to_user requires the entry's deck to be
    # owned by the entry's own user, and one_entry_per_player allows only one profile-less entry
    # per user per event — a distinct user per row is what a shared user could not give us.
    user = User.create!(email: "quiet-player-#{index}@example.com", password: "password123")
    deck = Deck.create!(user: user, name: "Quiet Deck #{index}", standard_pool: standard_pools(:twm_por))
    entry = user.tournament_entries.create!(tournament: @tournament, deck: deck)
    # A field list of its own per row too, and ownerless-and-shared rather than a reuse of the
    # entry's own deck: that is what Task 8's import actually produces (Deck requires an
    # ownerless deck to be shared and non-physical), so the fixture reflects reality rather than
    # merely satisfying a counter. Row#list_link reads this association, so it needs a distinct
    # row per standing for the same reason the archetype and the entry do.
    field_list = Deck.create!(
      name: "Quiet Field List #{index}", shared: true, standard_pool: standard_pools(:twm_por)
    )
    @tournament.standings.create!(
      player_name: "Quiet Player #{index}", division: "masters",
      placement: 100 + index, archetype: archetype, tournament_entry: entry, deck: field_list
    )
  end
end
