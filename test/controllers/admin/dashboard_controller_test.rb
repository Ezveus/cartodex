require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
  end

  test "the dashboard's recent decks render an ownerless deck" do
    decks(:field_list).update!(created_at: Time.current)

    get admin_root_path

    assert_response :success
    assert_select ".data-table-cell", text: "Tournament field list"
  end
end
