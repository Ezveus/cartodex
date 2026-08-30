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
end
