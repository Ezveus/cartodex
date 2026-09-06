require "test_helper"

# The screen where a human decides. Every test here is about the one thing the store is built
# around: a decision — a yes *or* a no — is a row, and nothing automatic may take it back.
class Admin::CardRolesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # There is no admin fixture: the panel's tests promote users(:one).
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
    @roles = CardLabel::ROLES.to_h do |attributes|
      [ attributes[:slug], CardLabel.create!(family: "role", **attributes) ]
    end
    @card = cards(:honedge)
  end

  # A label is about the card, so the screen is a list of cards and not of printings: budew_pre
  # and budew_asc are two rows in `cards` carrying one fingerprint, and offering them as two rows
  # would offer a second checkbox for a decision already made.
  test "the screen lists one row per fingerprint, not one per printing" do
    get admin_card_roles_path(played: "0", q: "budew")

    assert_response :success
    assert_select "##{row_id(cards(:budew_pre).fingerprint)}", 1
    assert_equal cards(:budew_pre).fingerprint, cards(:budew_asc).fingerprint
  end

  # The rows live in a Turbo Frame and the filter bar targets it. Without one the debounced field
  # navigates the whole page, and the caret is gone after every keystroke — on the control whose
  # whole job is turning 3023 fingerprints into 94. The app's three other filtered listings do
  # exactly this; a request test can at least hold the wiring.
  test "the rows sit in a frame the filter bar targets" do
    get admin_card_roles_path(played: "0", q: "budew")

    assert_select "turbo-frame##{Admin::CardRoles::IndexView::FRAME_ID} .data-table-row", minimum: 1
    assert_select "form.deck-filters[data-turbo-frame=?]", Admin::CardRoles::IndexView::FRAME_ID
  end

  # The filter that makes the first pass an evening's work rather than a month's: measured on the
  # production dump, the recorded lists play 94 fingerprints out of the catalogue's 3023. It is
  # the default because curating what nobody plays is work no reader of the report will ever see.
  test "it defaults to the cards a recorded list plays" do
    tournament_standings(:ash_masters).update!(deck: decks(:field_list))
    played = cards(:teal_mask_ogerpon_ex)

    get admin_card_roles_path

    assert_response :success
    assert_select "##{row_id(played.fingerprint)}", 1
    assert_select "##{row_id(@card.fingerprint)}", 0
  end

  test "ticking a role writes a curated decision" do
    patch admin_card_role_path(@card.fingerprint), params: { roles: [ "gust" ] },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assignment = @roles["gust"].assignments.sole

    assert_equal @card.fingerprint, assignment.fingerprint
    assert_equal "curated", assignment.source
    assert_not assignment.rejected
  end

  # The rule the whole store exists for. Unticking is a human saying "no, Iono is not a Gust", and
  # a deletion would say "nobody has looked at this yet" — which the next suggester run would then
  # answer by proposing it again, for ever.
  test "unticking a role writes a curated refusal and deletes nothing" do
    suggestion = @roles["gust"].assignments.create!(fingerprint: @card.fingerprint, source: "suggested")

    patch admin_card_role_path(@card.fingerprint), params: { roles: [ "draw" ] },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    refusal = @roles["gust"].assignments.sole

    assert_equal suggestion.id, refusal.id, "the refusal replaced the row instead of rewriting it"

    assert_equal "curated", refusal.source
    assert refusal.rejected
  end

  # A save is a statement about the whole card, not about the box that changed: every role left
  # unticked becomes a recorded refusal, which is what stops the suggester re-proposing the six
  # the human said no to by leaving them alone.
  test "a save decides every role on the row, not only the ticked ones" do
    patch admin_card_role_path(@card.fingerprint), params: { roles: [ "gust" ] },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal CardLabel::ROLES.size,
      CardLabelAssignment.where(fingerprint: @card.fingerprint, source: "curated").count
    assert_equal 1, CardLabelAssignment.active.where(fingerprint: @card.fingerprint).count
  end

  test "ticking a role a suggestion proposed promotes that row rather than adding one" do
    suggestion = @roles["gust"].assignments.create!(fingerprint: @card.fingerprint, source: "suggested")

    patch admin_card_role_path(@card.fingerprint), params: { roles: [ "gust" ] },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "curated", suggestion.reload.source
    assert_not suggestion.rejected
  end

  # The commonest gesture on a curation screen is agreeing with what is already ticked, and until
  # the row grew a Save button there was nothing to click for it: the form submitted on `change`
  # alone, so confirming meant ticking a role that is wrong — publishing it — and unticking it.
  test "a row can be saved without any box changing" do
    @roles["gust"].assignments.create!(fingerprint: @card.fingerprint, source: "suggested")

    patch admin_card_role_path(@card.fingerprint), params: { roles: [ "gust" ] },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "curated", @roles["gust"].assignments.sole.source
  end

  # The way back out, and the only deletion the app offers on an assignment: a save decides all
  # seven roles, so one misclick otherwise hides a card from the suggester for good. Deleting on
  # an *explicit* request is not the same act as deleting when a box is unticked — the second
  # would erase a refusal, which is the rule this store is built on.
  test "clearing a row's decisions hands the card back to the suggester" do
    @roles["gust"].assignments.create!(fingerprint: @card.fingerprint, source: "curated")
    @roles["draw"].assignments.create!(fingerprint: @card.fingerprint, source: "curated",
                                        rejected: true)
    kept = @roles["search"].assignments.create!(fingerprint: @card.fingerprint, source: "suggested")

    delete admin_card_role_path(@card.fingerprint),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal 0, CardLabelAssignment.curated.where(fingerprint: @card.fingerprint).count
    assert CardLabelAssignment.exists?(kept.id), "clearing took the machine's proposals with it"
  end

  # An HTML PATCH must not raise MissingTemplate *after* the seven rows have committed — the
  # DecksController#share lesson, on a form Turbo normally intercepts.
  test "a write without Turbo lands somewhere instead of 500ing over a committed decision" do
    patch admin_card_role_path(@card.fingerprint), params: { roles: [ "gust" ] }

    assert_redirected_to admin_card_roles_path
    assert_equal "curated", @roles["gust"].assignments.sole.source
  end

  # A fingerprint no card carries is a row the report can never join — the state
  # CardStats::GROUPING_KEY already refuses to invent. It is a 404 rather than a silent create.
  test "an unknown fingerprint is a 404, not a new row" do
    assert_no_difference "CardLabelAssignment.count" do
      patch admin_card_role_path("nothing_carries_this"), params: { roles: [ "gust" ] },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :not_found
  end

  # The write answers with the row the server holds, not with the box the browser ticked: a
  # refusal, a promotion and a plain tick all look identical in the DOM until the row comes back.
  test "a write answers with a Turbo Stream replacing that row" do
    patch admin_card_role_path(@card.fingerprint), params: { roles: [ "gust" ] },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %(target="#{row_id(@card.fingerprint)}"), response.body
  end

  test "suggest runs the rules and says what it wrote" do
    Card.create!(name: "Nest Ball", card_type: "Trainer", subtype: "Item", set_name: "TST",
                 set_number: "1", rarity: "Common",
                 effect: "Search your deck for a Basic Pokémon and put it onto your Bench.")

    post suggest_admin_card_roles_path

    assert_redirected_to admin_card_roles_path
    assert_equal 1, @roles["search"].assignments.count
    assert_match(/1 suggestion/, flash[:notice])
  end

  test "a non-admin cannot reach the screen" do
    sign_in users(:two)

    get admin_card_roles_path

    assert_redirected_to root_path
  end

  # The screen prints a checkbox per role per row, and reading either the assignments or the
  # printings row by row is the obvious way to write it. Two grouped reads instead, so the cost of
  # the page does not grow with the page.
  test "the screen costs the same number of queries however many rows it lists" do
    # One warm-up request first: Devise loads the session's user on the first request of a test
    # and not on the next, which is a one-off worth exactly one query and has nothing to do with
    # how many rows the page holds.
    get admin_card_roles_path(played: "0")
    small = count_queries { get admin_card_roles_path(played: "0") }
    5.times do |index|
      Card.create!(name: "Filler #{index}", card_type: "Trainer", subtype: "Item", set_name: "TST",
                   set_number: index.to_s, rarity: "Common", effect: "Draw 2 cards.")
    end
    large = count_queries { get admin_card_roles_path(played: "0") }

    assert_equal small, large, "query count grew with the page: #{small} -> #{large}"
  end

  private

  def row_id(fingerprint) = "card-role-#{fingerprint}"
end
