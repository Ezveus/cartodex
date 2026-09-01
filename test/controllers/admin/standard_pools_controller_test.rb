require "test_helper"

class Admin::StandardPoolsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
  end

  test "the index lists pools newest first with their bounds and marks" do
    # Created last, so it holds the highest id while carrying the newest release
    # date: an index ordered by anything but released_on would put it at the
    # bottom. Future-dated on purpose — this screen makes such a pool reachable,
    # and StandardPool.current must still resolve to twm_por.
    newest = StandardPool.create!(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: %w[I J], released_on: Date.current + 30, legal_on: Date.current + 44
    )

    get admin_standard_pools_path

    assert_response :success
    assert_match "TWM-POR (current)", response.body
    assert_match "TWM-ASC", response.body
    assert_match "G, H, I, J", response.body
    assert_operator response.body.index(newest.name), :<, response.body.index("TWM-POR"),
      "pools must be listed newest release first"
    assert_operator response.body.index("TWM-POR"), :<, response.body.index("TWM-ASC"),
      "pools must be listed newest release first"
  end

  # A set release moves only the upper bound, so the parts a human does not know
  # are pre-filled from the current pool. Typing them again is how a wrong pool
  # gets seeded.
  test "the new form pre-fills the lower bound and the marks from the current pool" do
    get new_admin_standard_pool_path

    assert_response :success
    assert_match "G, H, I, J", response.body
    assert_select "select[name=?] option[selected][value=?]",
      "standard_pool[first_card_set_id]", card_sets(:twm).id.to_s
  end

  test "creates a pool" do
    assert_difference "StandardPool.count", 1 do
      post admin_standard_pools_path, params: { standard_pool: {
        first_card_set_id: card_sets(:asc).id,
        last_card_set_id: card_sets(:por).id,
        regulation_marks: "H, I, J",
        released_on: "2026-06-01",
        legal_on: "2026-06-15"
      } }
    end

    pool = StandardPool.order(:created_at).last
    assert_equal %w[H I J], pool.regulation_marks
    assert_equal "ASC-POR", pool.name
  end

  # The edit form has to show the marks as the text the parser accepts, and the
  # update has to run that parser too — parsing only on create would silently
  # store the raw string.
  test "the edit form shows the marks as text and the update parses them back" do
    pool = standard_pools(:twm_asc)

    get edit_admin_standard_pool_path(pool)

    assert_response :success
    assert_match "G, H, I", response.body

    patch admin_standard_pool_path(pool), params: { standard_pool: {
      first_card_set_id: pool.first_card_set_id,
      last_card_set_id: pool.last_card_set_id,
      regulation_marks: "h, i, j",
      released_on: pool.released_on.to_s,
      legal_on: pool.legal_on.to_s
    } }

    assert_redirected_to admin_standard_pools_path
    assert_equal %w[H I J], pool.reload.regulation_marks
  end

  test "rejects a duplicate bound pair" do
    assert_no_difference "StandardPool.count" do
      post admin_standard_pools_path, params: { standard_pool: {
        first_card_set_id: card_sets(:twm).id,
        last_card_set_id: card_sets(:por).id,
        regulation_marks: "H, I, J",
        released_on: "2026-06-01",
        legal_on: "2026-06-15"
      } }
    end

    assert_response :unprocessable_entity
  end

  # restrict_with_error, not nullify: a NULL anchor on a Standard deck is
  # unsavable on its next edit.
  test "refuses to delete a pool decks are anchored to" do
    pool = standard_pools(:twm_por)

    assert_predicate pool.decks, :any?

    assert_no_difference "StandardPool.count" do
      delete admin_standard_pool_path(pool)
    end

    assert_redirected_to admin_standard_pools_path
    # The flash text, not just the surviving row: tournaments are anchored to this
    # pool too and restrict on their own, so the count alone would stay steady
    # even if the decks association stopped refusing.
    assert_match "deck", flash[:alert]
  end

  # Delete is why the action exists: the refusal above only proves the guard, never that a
  # pool nothing points at actually goes. twm_asc is referenced by no fixture — decks.yml
  # and tournaments.yml both anchor on twm_por — so it is the one deletable pool.
  test "deletes a pool nothing is anchored to" do
    pool = standard_pools(:twm_asc)

    assert_empty pool.decks
    assert_empty pool.tournaments

    assert_difference "StandardPool.count", -1 do
      delete admin_standard_pool_path(pool)
    end

    assert_redirected_to admin_standard_pools_path
    assert_equal "Standard pool deleted.", flash[:notice]
  end

  test "requires an admin" do
    @admin.update!(admin: false)

    get admin_standard_pools_path

    assert_response :redirect
  end
end
