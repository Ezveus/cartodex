require "test_helper"

class Admin::CardSetsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
  end

  # The URL is what CardSets::ImportJob runs from, and storing it is what lets /admin/imports
  # replay the run (Imports::Replayer) without rebuilding it from the label.
  test "importing a set records the URL it was read from" do
    assert_enqueued_with(job: CardSets::ImportJob) do
      post import_admin_card_sets_path, params: { url: "https://limitlesstcg.com/cards/MEG" }
    end

    import = Import.last
    assert_equal "card_set", import.kind
    assert_equal "MEG", import.label
    assert_equal({ "url" => "https://limitlesstcg.com/cards/MEG" }, import.replay_params)
  end
end
