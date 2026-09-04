require "test_helper"

class Admin::ImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
  end

  # The decklist text is not stored anywhere — an Import carries a label, not a payload — so
  # there is nothing to re-run. Refused explicitly rather than left to fall through the case,
  # which destroys the old row and enqueues nothing.
  test "a field-list import cannot be retried" do
    import = users(:one).imports.create!(kind: "standing_list", label: "Ash's list", status: "failed")

    assert_no_difference -> { Import.count } do
      post retry_admin_import_path(import)
    end

    assert_redirected_to admin_imports_path
    assert_match(/cannot be retried/, flash[:alert])
    assert Import.exists?(import.id)
  end
end
