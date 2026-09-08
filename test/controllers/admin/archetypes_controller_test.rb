require "test_helper"

class Admin::ArchetypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
    @archetype = archetypes(:budew_ogerpon)
  end

  # An archetype designates an exact printing, and the pickers say so ("Name (SET
  # NUMBER)"). The admin is where that choice is inspected and corrected, so a
  # bare name here leaves two archetypes built from two printings of the same
  # card indistinguishable.
  test "the index names the printing each member card is" do
    get admin_archetypes_path

    assert_response :success
    assert_match "Budew (PRE 4)", response.body
    assert_match "Teal Mask Ogerpon ex (TWM 25)", response.body
  end

  test "the show page names the printing each member card is" do
    get admin_archetype_path(@archetype)

    assert_response :success
    assert_match "Budew (PRE 4)", response.body
    assert_match "Teal Mask Ogerpon ex (TWM 25)", response.body
  end

  # The text input is the one the user retypes over. Pre-filled with a bare name
  # it looks like the whole value, so leaving it alone — or retyping the same
  # name without picking from the dropdown — reads as a deliberate confirmation
  # of a printing it never showed.
  test "the edit form pre-fills each card input with its printing" do
    get edit_admin_archetype_path(@archetype)

    assert_response :success
    assert_select "input[type=text][value=?]", "Budew (PRE 4)"
    assert_select "input[type=text][value=?]", "Teal Mask Ogerpon ex (TWM 25)"
  end

  # restrict_with_error, not the destroy call it replaced: a standing is another member's
  # public record of a real placement, so deleting the archetype tag must refuse rather than
  # silently take that record with it.
  test "refuses to delete an archetype named on a tournament standing" do
    archetype = archetypes(:standings_marker)
    assert_predicate archetype.tournament_standings, :any?, "sanity: fixture standings reference it"

    assert_no_difference -> { Archetype.count } do
      delete admin_archetype_path(archetype)
    end

    assert_redirected_to admin_archetype_path(archetype)
    assert_equal "This archetype is still named on 2 tournament standings.", flash[:alert]
  end

  # Admin::DecksController had to make the same move when a deck became addressable by its key:
  # `admin_archetype_path` goes through `Archetype#to_param`, so `find` would cast the slug to 0
  # and 404 every screen here.
  test "an archetype's admin URL names its slug and resolves" do
    assert_equal "/admin/archetypes/budew-teal-mask-ogerpon-ex", admin_archetype_path(@archetype)

    get "/admin/archetypes/budew-teal-mask-ogerpon-ex"

    assert_response :success
  end

  test "renaming an archetype redirects to its new address" do
    patch admin_archetype_path(@archetype),
      params: { archetype: { name: "Budew Toolbox", primary_card_id: @archetype.primary_card_id,
                             secondary_card_id: @archetype.secondary_card_id } }

    assert_redirected_to "/admin/archetypes/budew-toolbox"
    assert_equal "budew-toolbox", @archetype.reload.slug
  end

  # The slug is UNIQUE, so a rename onto a name another archetype already owns modulo
  # punctuation is refused — and refused on :name, the only field this form has.
  test "a rename whose address is already taken is refused on the name field" do
    patch admin_archetype_path(@archetype),
      params: { archetype: { name: "Teal Mask Ogerpon ex",
                             primary_card_id: @archetype.primary_card_id,
                             secondary_card_id: @archetype.secondary_card_id } }

    assert_response :unprocessable_entity
    assert_match "/archetypes/teal-mask-ogerpon-ex", response.body
    assert_equal "budew-teal-mask-ogerpon-ex", @archetype.reload.slug
  end

  test "deletes an archetype no standing names" do
    assert_difference -> { Archetype.count }, -1 do
      delete admin_archetype_path(@archetype)
    end

    assert_redirected_to admin_archetypes_path
    assert_equal "Archetype deleted.", flash[:notice]
  end
end
