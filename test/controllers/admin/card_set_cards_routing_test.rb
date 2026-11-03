require "test_helper"

# Cards are created inside a set and edited at their own address: only `new` and `create` nest.
# Asked through requests by a signed-in admin, because the admin routes sit inside
# `authenticate :user`, whose constraint needs the Warden a bare route lookup does not have.
class Admin::CardSetCardsRoutingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    users(:one).update!(admin: true)
    sign_in users(:one)
    @set = card_sets(:por)
  end

  test "new and create nest under the set" do
    assert_equal "/admin/card_sets/#{@set.id}/cards/new", new_admin_card_set_card_path(@set)
    assert_equal "/admin/card_sets/#{@set.id}/cards", admin_card_set_cards_path(@set)

    get "/admin/card_sets/#{@set.id}/cards/new"
    assert_response :success
  end

  test "nothing else nests under the set" do
    card = cards(:honedge)

    get "/admin/card_sets/#{@set.id}/cards/#{card.id}/edit"
    assert_response :not_found
    get "/admin/card_sets/#{@set.id}/cards"
    assert_response :not_found
    get "/admin/card_sets/#{@set.id}/cards/#{card.id}"
    assert_response :not_found
  end
end
