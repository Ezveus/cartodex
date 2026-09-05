require "test_helper"

class Tournaments::StandingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @tournament = tournaments(:one)
    @standing = tournament_standings(:giovanni_masters) # created_by users(:two)
    sign_in @user
  end

  test "a member records a standing on an event they did not catalogue" do
    sign_in users(:two) # tournaments(:one) was catalogued by users(:one)

    assert_difference -> { TournamentStanding.count }, 1 do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "Brock", division: "masters", placement: 4,
        wins: 6, losses: 2, ties: 1, archetype_id: archetypes(:ogerpon).id
      } }
    end

    standing = TournamentStanding.order(:id).last
    assert_redirected_to_row standing
    assert_equal "Brock", standing.player_name
    assert_equal "brock", standing.player_name_normalized
    assert_equal users(:two), standing.created_by
  end

  # Since the sheet grew a pager, "back to the event" is the top of page one — which need not hold
  # the row that was just written. A member who records the fifty-first standing has to be answered
  # with the page it is on, or their own row is invisible and they will type it again.
  test "recording a row on the second page of the sheet lands on that page" do
    TournamentStanding::SHEET_PER_PAGE.times do |i|
      @tournament.standings.create!(player_name: "Filler #{i}", division: "masters", placement: i + 1,
        archetype: archetypes(:standings_marker))
    end

    post tournament_standings_path(@tournament), params: { tournament_standing: {
      player_name: "Latecomer", division: "masters", placement: 900,
      archetype_id: archetypes(:standings_marker).id
    } }

    standing = TournamentStanding.find_by!(player_name: "Latecomer")
    assert_equal 2, TournamentStanding.page_of(standing)
    assert_redirected_to tournament_path(@tournament, page: 2,
      anchor: Tournaments::Standings::Row.dom_id(standing))
  end

  # Saving returns the member to their row; cancelling should not cost them their place. A new row
  # has no place yet, so its Cancel still points at the event.
  test "Cancel returns to the row being edited, not to the top of the sheet" do
    get edit_tournament_standing_path(@tournament, @standing)

    assert_select "a.btn-secondary[href=?]",
      tournament_path(@tournament, **Tournaments::Standings::Row.sheet_position(@standing)), text: "Cancel"

    get new_tournament_standing_path(@tournament)

    assert_select "a.btn-secondary[href=?]", tournament_path(@tournament), text: "Cancel"
  end

  # Deleting the only row of the last page leaves a ?page= that no longer exists. #show clamps what
  # it *renders*, so the page looks right — but the address bar keeps saying page two, and a reload
  # or a shared link repeats it.
  test "deleting the last row of the last page does not leave a page behind" do
    # Two short of a full page, because the fixtures already put two rows on this event: the row
    # created next is then the fifty-first and the only one on page two.
    (TournamentStanding::SHEET_PER_PAGE - 2).times do |i|
      @tournament.standings.create!(player_name: "Filler #{i}", division: "masters", placement: i + 1,
        archetype: archetypes(:standings_marker))
    end
    last = @tournament.standings.create!(player_name: "Only On Page Two", division: "masters",
      placement: 900, archetype: archetypes(:standings_marker))
    assert_equal 2, TournamentStanding.page_of(last)

    delete tournament_standing_path(@tournament, last)

    # Page one, and the bare URL: page two no longer exists.
    assert_redirected_to tournament_path(@tournament)
  end

  # Wiki governance, decision 3: correcting a public record is not a property question.
  test "a member may edit and delete a row another member typed" do
    patch tournament_standing_path(@tournament, @standing),
      params: { tournament_standing: { placement: 3 } }

    assert_redirected_to_row @standing
    assert_equal 3, @standing.reload.placement

    assert_difference -> { TournamentStanding.count }, -1 do
      delete tournament_standing_path(@tournament, @standing)
    end
  end

  test "a row belonging to another event 404s rather than rendering under this header" do
    get edit_tournament_standing_path(tournaments(:two), @standing)

    assert_response :not_found
  end

  # Without this, the wiki edit form would let any member attach their own participation to a row
  # naming somebody else, or detach yours. The link is written only by claim/unclaim.
  test "tournament_entry_id is not mass-assignable" do
    patch tournament_standing_path(@tournament, @standing), params: { tournament_standing: {
      placement: 5, tournament_entry_id: tournament_entries(:one).id
    } }

    assert_redirected_to_row @standing
    assert_equal 5, @standing.reload.placement
    assert_nil @standing.tournament_entry_id
  end

  # F1: the event's division field sizes used to be permitted by nothing and rendered by no
  # form, so this validation was exercised only by tests that set the column directly and never
  # by a real request — the field could never actually be set in production, and this test would
  # not have caught that if it did the same thing. So the field size is set here through
  # TournamentsController#update itself, exactly as a member would from the event form: if
  # tournament_params ever stops permitting the three counts, this goes red because the field
  # stays nil and the placement below is silently accepted.
  test "the placement cap fires end-to-end once the event's division field size is set" do
    patch tournament_path(@tournament), params: { tournament: { masters_participant_count: 8 } }
    assert_equal 8, @tournament.reload.masters_participant_count

    assert_no_difference -> { TournamentStanding.count } do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "Brock", division: "masters", placement: 9,
        archetype_id: archetypes(:ogerpon).id
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors li", text: /masters field of 8/
  end

  test "the uniqueness error renders a link to the clashing row" do
    assert_no_difference -> { TournamentStanding.count } do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "  GIOVANNI  ", division: "masters", archetype_id: archetypes(:ogerpon).id
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".form-hint", text: /already has a standing/
    # At the clashing row, not at the event: telling a member their name is taken and then landing
    # them on a page that does not hold the row is the whole hint wasted.
    assert_select ".form-hint a[href=?]",
      tournament_path(@tournament, **Tournaments::Standings::Row.sheet_position(tournament_standings(:giovanni_masters)))
  end

  test "new prefills from the reader's own participation" do
    get new_tournament_standing_path(@tournament, tournament_entry_id: tournament_entries(:one).id)

    assert_response :success
    # tournament_profiles(:ash) was born in 2014, so the 2026 season puts them in juniors.
    assert_select "input[name=?][value=?]", "tournament_standing[player_name]", "Ash Ketchum"
    assert_select "select[name=?] option[selected][value=?]", "tournament_standing[division]", "junior"
    assert_select "input[name=?][value=?]", "tournament_standing[placement]", "33"
    # The hidden field is what carries the link through to #create, outside the permitted params.
    assert_select "input[type=hidden][name=tournament_entry_id][value=?]",
      tournament_entries(:one).id.to_s
  end

  test "prefilling from another member's participation 404s" do
    get new_tournament_standing_path(@tournament,
      tournament_entry_id: tournament_entries(:shared_event).id) # users(:two)'s

    assert_response :not_found
  end

  test "creating from a prefill links the participation" do
    post tournament_standings_path(@tournament), params: {
      tournament_entry_id: tournament_entries(:one).id,
      tournament_standing: {
        player_name: "Ash Ketchum", division: "junior",
        archetype_id: archetypes(:ogerpon).id
      }
    }

    assert_redirected_to_row TournamentStanding.order(:id).last
    assert_equal tournament_entries(:one), TournamentStanding.order(:id).last.tournament_entry
  end

  test "a signed-out request is sent to sign in and writes nothing" do
    sign_out @user
    placement_was = @standing.placement

    post tournament_standings_path(@tournament), params: { tournament_standing: {
      player_name: "Brock", division: "masters", archetype_id: archetypes(:ogerpon).id
    } }
    assert_redirected_to new_user_session_path

    patch tournament_standing_path(@tournament, @standing),
      params: { tournament_standing: { placement: 1 } }
    assert_redirected_to new_user_session_path

    delete tournament_standing_path(@tournament, @standing)
    assert_redirected_to new_user_session_path

    assert_equal placement_was, @standing.reload.placement
    assert_equal 2, TournamentStanding.count
  end

  test "the event page offers the write controls to a member and none to a visitor" do
    get tournament_path(@tournament)
    assert_select "a[href=?]", new_tournament_standing_path(@tournament), text: "Add a standing"
    assert_select "a[href=?]", edit_tournament_standing_path(@tournament, @standing)

    sign_out @user
    get tournament_path(@tournament)
    assert_select "a[href=?]", new_tournament_standing_path(@tournament), count: 0
    assert_select "a[href=?]", edit_tournament_standing_path(@tournament, @standing), count: 0
  end

  test "a member claims a row somebody else typed" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:one).id)

    assert_redirected_to_row @standing
    assert_equal tournament_entries(:one), @standing.reload.tournament_entry
  end

  test "claiming with another member's participation 404s and links nothing" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:shared_event).id) # users(:two)'s

    assert_response :not_found
    assert_nil @standing.reload.tournament_entry_id
  end

  test "claiming with a participation from another event 404s" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:two).id) # users(:two)'s, and another event

    assert_response :not_found
  end

  # F3: the partial UNIQUE index on tournament_entry_id is what stops a member publishing
  # themselves twice under two spellings of their own name, which the player-name key cannot
  # see — but this table used to mirror it with no readable validation, so re-opening the
  # still-bookmarkable new?tournament_entry_id=E under a different name, or claiming from two
  # tabs, raised ActiveRecord::RecordNotUnique straight through the request stack: a 500. This
  # asserts the request-level behaviour changed to a redirect with an alert; the database
  # guarantee itself now has its own test in TournamentStandingTest, on a callback-bypassing
  # write, since that is a property of the index and not of this controller.
  test "claiming a participation that already backs another row redirects with an alert" do
    @standing.update!(tournament_entry: tournament_entries(:one))

    post claim_tournament_standing_path(@tournament, tournament_standings(:ash_masters),
      tournament_entry_id: tournament_entries(:one).id)

    # The refused row is still standing, so the alert has to arrive next to it rather than at the
    # top of page one.
    assert_redirected_to_row tournament_standings(:ash_masters)
    assert_match(/already linked/, flash[:alert])
    assert_nil tournament_standings(:ash_masters).reload.tournament_entry_id
    assert_equal tournament_entries(:one), @standing.reload.tournament_entry
  end

  # The same failure reachable from the ordinary create path: publishing from a prefill whose
  # participation has, in the meantime, already been linked to a different row.
  test "creating from a prefill whose participation already backs another standing re-renders the form" do
    @standing.update!(tournament_entry: tournament_entries(:one))

    assert_no_difference -> { TournamentStanding.count } do
      post tournament_standings_path(@tournament), params: {
        tournament_entry_id: tournament_entries(:one).id,
        tournament_standing: {
          player_name: "Ash Ketchum", division: "junior", archetype_id: archetypes(:ogerpon).id
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors li", text: /already linked/
  end

  test "the member whose participation is linked may sever the link" do
    @standing.update!(tournament_entry: tournament_entries(:one))

    delete unclaim_tournament_standing_path(@tournament, @standing)

    assert_redirected_to_row @standing
    assert_nil @standing.reload.tournament_entry_id
  end

  # The one owner-scoped rule in this controller: anybody may correct the public data on a row,
  # only its claimant may unlink it.
  test "another member may not sever somebody else's link" do
    @standing.update!(tournament_entry: tournament_entries(:one)) # users(:one)'s
    sign_in users(:two)

    delete unclaim_tournament_standing_path(@tournament, @standing)

    # A redirect with an alert, not a 403 and not a 404: an event and its sheet are public, so the
    # refusal has somewhere to send the member — the same answer TournamentsController gives a
    # member who may not edit an event. See the controller's own refuse_with_redirect.
    assert_redirected_to tournament_path(@tournament)
    assert_match(/can unlink it/, flash[:alert])
    assert_equal tournament_entries(:one), @standing.reload.tournament_entry
  end

  # A row can go invalid after it was written: the event's per-division field sizes are editable
  # and cap a placement already recorded. update! re-runs *every* validation, not only the one
  # being changed, so unlinking such a row raised RecordInvalid — which nothing here rescues, so
  # the member's "Unlink" click answered with a 500.
  test "severing a link still works on a row the event's field size has since invalidated" do
    @standing.update!(tournament_entry: tournament_entries(:one))
    @tournament.update_column(:masters_participant_count, 5) # @standing is placed 7th
    refute_predicate @standing.reload, :valid?

    delete unclaim_tournament_standing_path(@tournament, @standing)

    assert_redirected_to_row @standing
    assert_nil @standing.reload.tournament_entry_id
  end

  # The other half of the same premise. A claim refused by a validation that is not the link rule
  # used to build its alert from errors[:tournament_entry], which is empty here — so the member
  # was redirected with a blank alert and no idea why the button did nothing.
  test "a claim refused by a stale placement says why" do
    @tournament.update_column(:masters_participant_count, 5) # ash_masters is placed 33rd

    post claim_tournament_standing_path(@tournament, tournament_standings(:ash_masters),
      tournament_entry_id: tournament_entries(:one).id)

    assert_redirected_to_row tournament_standings(:ash_masters)
    assert_match(/masters field/, flash[:alert])
    assert_nil tournament_standings(:ash_masters).reload.tournament_entry_id
  end

  test "a decklist on the form opens an import and enqueues the job" do
    assert_difference -> { Import.count }, 1 do
      assert_enqueued_with(job: Tournaments::StandingListImportJob) do
        post tournament_standings_path(@tournament), params: { tournament_standing: {
          player_name: "Brock", division: "masters", archetype_id: archetypes(:ogerpon).id
        }, decklist: "4 Doublade TWM 62" }
      end
    end

    import = Import.order(:id).last
    assert_equal "standing_list", import.kind
    assert_equal @user, import.user
    # The row exists before its list does, which is the point: a failed import must not lose the
    # standing somebody typed.
    assert_equal "Brock", TournamentStanding.order(:id).last.player_name
  end

  test "no decklist enqueues nothing" do
    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs(only: Tournaments::StandingListImportJob) do
        post tournament_standings_path(@tournament), params: { tournament_standing: {
          player_name: "Brock", division: "masters", archetype_id: archetypes(:ogerpon).id
        }, decklist: "   " }
      end
    end
  end

  test "a refused save enqueues nothing" do
    assert_no_difference -> { Import.count } do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "", division: "masters", archetype_id: archetypes(:ogerpon).id
      }, decklist: "4 Doublade TWM 62" }
    end

    assert_response :unprocessable_entity
  end

  # Phlex dasherizes Symbol attribute values, and this repo has shipped that bug once (an OAuth
  # form whose hidden fields all rendered dashed, params[:client_id] permanently nil, seven tests
  # green because each hand-built its params). So this reads the field's *actual* rendered name
  # off the markup rather than assuming "decklist", and posts under that name — a hand-built
  # params hash would pass even if the field silently rendered as "decklist" with dashes.
  test "the decklist field's rendered name is what the controller reads" do
    get new_tournament_standing_path(@tournament)
    field = css_select("textarea#decklist").first
    assert_not_nil field, "the form must render a decklist textarea"
    field_name = field["name"]

    assert_difference -> { Import.count }, 1 do
      assert_enqueued_with(job: Tournaments::StandingListImportJob) do
        post tournament_standings_path(@tournament), params: { tournament_standing: {
          player_name: "Misty", division: "masters", archetype_id: archetypes(:ogerpon).id
        }, field_name => "4 Doublade TWM 62" }
      end
    end
  end

  # prefill_attributes yields no division at all for a participation with no TournamentProfile —
  # profile&.division is nil and .compact drops it — and DIVISIONS runs junior-senior-masters, so
  # a select with no explicit selection let the browser pre-pick Junior and silently published a
  # Masters player as a Junior.
  test "the division select defaults to masters, not to the first option" do
    sign_in users(:two) # tournament_entries(:shared_event) carries no tournament_profile
    assert_nil tournament_entries(:shared_event).tournament_profile

    get new_tournament_standing_path(@tournament,
      tournament_entry_id: tournament_entries(:shared_event).id)

    assert_select "select[name=?] option[selected]", "tournament_standing[division]",
      text: "Masters", count: 1
  end

  # The other half of the same select, and the one that loses data rather than merely mislabelling
  # it. This form is shared by new and edit, standings are wiki-governed, and standing_params
  # permits :division — so a select built from AGE_DIVISIONS alone renders no option matching
  # "open", the browser pre-selects the first one, and the division travels back to the server on
  # every save whether or not anybody touched it. A member opening an imported online row to fix a
  # typo in the player name would silently refile an online result as a Junior one.
  #
  # The submitted value is read off the *rendered* form the way the browser would choose it — the
  # pre-selected option, or the first when nothing is pre-selected — rather than hand-built, since
  # a hand-built "open" would pass with the bug in place.
  test "editing an imported online standing through the form leaves its division open" do
    standing = online_standing

    get edit_tournament_standing_path(standing.tournament, standing)
    assert_response :success

    options = css_select("select[name='tournament_standing[division]'] option")
    assert_not_empty options
    chosen = options.find { |option| option["selected"] } || options.first

    patch tournament_standing_path(standing.tournament, standing), params: {
      tournament_standing: { player_name: "Jose Rueda", division: chosen["value"] }
    }

    standing.reload
    assert_equal "Jose Rueda", standing.player_name
    assert_equal "open", standing.division
  end

  # §4 fixed the *edit* case — a select carrying the row's own value — and the new-row case is a
  # different door onto the same lie: a new standing takes its division from the reader's
  # TournamentProfile or from DEFAULT_DIVISION, neither of which can produce "open", so an online
  # event's form offered junior/senior/masters and a member completing an imported sheet filed an
  # online result under an age division that Archetypes::Performance#by_division then reports as
  # fact. The options are asked of the event: an online one has "open" and no age divisions.
  test "the new-standing form on an online event offers Open and no age division" do
    event = online_event

    get new_tournament_standing_path(event)

    assert_response :success
    assert_select "select[name=?] option", "tournament_standing[division]", count: 1
    assert_select "select[name=?] option[selected][value=?]",
      "tournament_standing[division]", "open", count: 1
  end

  # The one door left open into the defect §4 closed. prefill_attributes copies the member's
  # Play! Pokémon age division off their participation, `division_options` then adds it back as the
  # row's "own" value — correct for the edit case it was written for — and `selected:` prefers it
  # over "open". So the form offered Open *and* Masters, with Masters pre-selected, and a member
  # publishing their participation at an online event filed it under an age division that event
  # does not have. Narrow (it needs an entry at that event, which the page no longer invites) and
  # real, since no policy refuses one.
  test "prefilling from a participation never carries an age division onto an online event" do
    event = online_event
    entry = @user.tournament_entries.create!(
      tournament: event, deck: decks(:one), tournament_profile: tournament_profiles(:ash)
    )

    get new_tournament_standing_path(event, tournament_entry_id: entry.id)

    assert_response :success
    assert_select "select[name=?] option", "tournament_standing[division]", count: 1
    assert_select "select[name=?] option[selected][value=?]",
      "tournament_standing[division]", "open", count: 1
    # The rest of the prefill still works — this drops one key, not the feature.
    assert_select "input[name=?][value=?]",
      "tournament_standing[player_name]", tournament_profiles(:ash).player_name
  end

  # The negative control, both halves: a paper event must still be offered its three age
  # divisions and must never be offered "open" — the rule §4 wrote, which this change must not
  # trade for the mirror image of the same lie.
  test "the new-standing form on a paper event still offers the three age divisions and not Open" do
    get new_tournament_standing_path(@tournament)

    assert_response :success
    assert_select "select[name=?] option", "tournament_standing[division]", count: 3
    assert_select "select[name=?] option[value=?]",
      "tournament_standing[division]", "open", count: 0
  end

  # The end-to-end half, and the value posted is read off the *rendered* form the way a browser
  # would choose it — the pre-selected option, or the first when nothing is pre-selected — rather
  # than hand-built, since a hand-built "open" would pass with the bug in place.
  test "a member adding a row to an imported online sheet files it under no age division" do
    event = online_event

    get new_tournament_standing_path(event)
    options = css_select("select[name='tournament_standing[division]'] option")
    assert_not_empty options
    chosen = options.find { |option| option["selected"] } || options.first

    assert_difference -> { TournamentStanding.count }, 1 do
      post tournament_standings_path(event), params: { tournament_standing: {
        player_name: "Aruarupokeka", division: chosen["value"], placement: 3,
        archetype_id: archetypes(:ogerpon).id
      } }
    end

    standing = event.standings.order(:id).last
    assert_equal "open", standing.division
    assert_not_includes TournamentStanding::AGE_DIVISIONS, standing.division
  end

  test "the event page shows the reader's field-list import in flight" do
    @user.imports.create!(kind: "standing_list", label: "Brock's list", tournament: @tournament)

    get tournament_path(@tournament)

    assert_select "#importing-standings .importing-item", text: /Brock's list/
  end

  # Scoped by event, not merely by kind. Unscoped, an import started at one event was listed under
  # every other event's "Importing…" heading — and since the item's DOM id is importing-<import
  # id>, that other event's completion broadcast then removed a row from this page.
  test "an import in flight at another event is not listed on this one" do
    other = tournaments(:two)
    assert_not_equal other, @tournament
    @user.imports.create!(kind: "standing_list", label: "Brock's list", tournament: other)

    get tournament_path(@tournament)

    assert_select "#importing-standings .importing-item", count: 0
  end

  # The enqueue has to hand the job ids: a standing (or its event) may be deleted while the job
  # waits, and GlobalID deserialization of a deleted record raises before #perform is entered,
  # where no rescue inside it can see the failure — the Import would stay "pending" forever.
  test "the import job is enqueued with ids, never with records" do
    form = get_standing_form
    field_name = form.at_css("textarea")["name"]

    post tournament_standings_path(@tournament), params: { tournament_standing: {
      player_name: "Misty", division: "masters", archetype_id: archetypes(:ogerpon).id
    }, field_name => "4 Doublade TWM 62" }

    standing = @tournament.standings.find_by(player_name: "Misty")
    import = Import.order(:id).last
    assert_equal @tournament, import.tournament
    enqueued = enqueued_jobs.find { |j| j["job_class"] == "Tournaments::StandingListImportJob" }
    assert_equal [ standing.id, "4 Doublade TWM 62", @user.id, import.id ], enqueued["arguments"]
  end

  private

  # Every write that leaves a row standing now answers with the page that row falls on, anchored to
  # the row itself: on a sheet with a pager, plain `tournament_path` is the top of page one, which
  # is not where the member was and need not hold what they just did.
  def assert_redirected_to_row(standing)
    page = TournamentStanding.page_of(standing)
    assert_redirected_to tournament_path(@tournament, page: (page unless page == 1),
      anchor: Tournaments::Standings::Row.dom_id(standing))
  end

  def get_standing_form
    get new_tournament_standing_path(@tournament)
    Nokogiri::HTML(response.body)
  end

  # What the online import writes: an event that is `online`, forced to tier "other" and carrying
  # an open field size. Built here rather than as a fixture because public_access_test.rb asserts
  # hard record counts.
  def online_event
    Tournament.create!(
      name: "Pumpkaweekly #12", date: Date.new(2026, 4, 18), tier: "other",
      format: "other", other_format_name: "Standard (Online)", online: true,
      open_participant_count: 259
    )
  end

  # One row of such an event's imported sheet, in the "open" division.
  def online_standing
    online_event.standings.create!(
      player_name: "JRobrueda", division: "open", placement: 2,
      wins: 8, losses: 0, ties: 0, archetype: archetypes(:standings_marker)
    )
  end
end
