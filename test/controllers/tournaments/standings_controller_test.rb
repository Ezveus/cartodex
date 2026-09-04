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

    assert_redirected_to tournament_path(@tournament)
    standing = TournamentStanding.order(:id).last
    assert_equal "Brock", standing.player_name
    assert_equal "brock", standing.player_name_normalized
    assert_equal users(:two), standing.created_by
  end

  # Wiki governance, decision 3: correcting a public record is not a property question.
  test "a member may edit and delete a row another member typed" do
    patch tournament_standing_path(@tournament, @standing),
      params: { tournament_standing: { placement: 3 } }

    assert_redirected_to tournament_path(@tournament)
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

    assert_redirected_to tournament_path(@tournament)
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
    assert_select ".form-hint a[href=?]", tournament_path(@tournament)
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

    assert_redirected_to tournament_path(@tournament)
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

    assert_redirected_to tournament_path(@tournament)
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

    assert_redirected_to tournament_path(@tournament)
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

    assert_redirected_to tournament_path(@tournament)
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

    assert_redirected_to tournament_path(@tournament)
    assert_nil @standing.reload.tournament_entry_id
  end

  # The other half of the same premise. A claim refused by a validation that is not the link rule
  # used to build its alert from errors[:tournament_entry], which is empty here — so the member
  # was redirected with a blank alert and no idea why the button did nothing.
  test "a claim refused by a stale placement says why" do
    @tournament.update_column(:masters_participant_count, 5) # ash_masters is placed 33rd

    post claim_tournament_standing_path(@tournament, tournament_standings(:ash_masters),
      tournament_entry_id: tournament_entries(:one).id)

    assert_redirected_to tournament_path(@tournament)
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

  def get_standing_form
    get new_tournament_standing_path(@tournament)
    Nokogiri::HTML(response.body)
  end
end
