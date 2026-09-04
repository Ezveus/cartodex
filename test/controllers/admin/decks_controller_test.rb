require "test_helper"

class Admin::DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
  end

  # All three admin deck listings printed `deck.user.email`, which is a NoMethodError the moment
  # a deck has no owner.
  test "the deck index renders an ownerless deck" do
    get admin_decks_path

    assert_response :success
    assert_select ".data-table-cell", text: "Tournament field list"
  end

  test "the deck show page renders an ownerless deck" do
    get admin_deck_path(decks(:field_list))

    assert_response :success
    assert_select "p", text: /Tournament field list/
  end
end
