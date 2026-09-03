require "test_helper"

# `/admin/jobs` mounts the MissionControl::Jobs engine, and it is the one page of the app whose
# markup lives inside somebody else's gem: `app/views/layouts/mission_control/jobs/`
# `_application_selection.html.erb` overrides the engine's own partial and leans on three things
# the engine owns — its two `application_selection/*` sub-partials and its `selectable_applications`
# helper. Nothing in the suite had ever loaded the page, so a bump that renamed any of them would
# have shipped a 500 past a green CI (the 1.1.0 → 1.2.0 bump rewrote that very partial upstream).
#
# The gate is worth pinning for the same reason: the mount sits behind a lambda constraint in
# `config/routes.rb`, and a constraint on a `mount` has no controller callback behind it — the
# engine's controllers inherit the app's `ApplicationController` (`base_controller_class`), whose
# `authenticate_user!` says nothing about `admin?`. Delete the constraint and every signed-in user
# gets the job dashboard, with nothing else to stop them.
class AdminJobsDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
  end

  test "an admin gets the dashboard, rendered through the app's own override" do
    # Read before the request: afterwards the session's url_options carry the engine's script_name,
    # and every app helper would generate a path under /admin/jobs.
    admin_root = admin_root_path

    sign_in @admin

    get mission_control_jobs_path

    assert_response :success
    back = css_select(".navbar-start a").find { |link| link.text.strip == "Back to admin" }
    assert back, "the app's _application_selection override did not render"
    # Compare paths, not hrefs: the engine appends its own server_id to everything it generates.
    assert_equal admin_root, URI.parse(back["href"]).path
  end

  test "a signed-in non-admin has no route to the dashboard" do
    non_admin = users(:two)
    non_admin.update!(admin: false)
    sign_in non_admin

    get mission_control_jobs_path

    # Not a 403: the constraint rejects before routing resolves, so the mount does not exist.
    assert_response :not_found
  end

  test "a visitor is sent to sign in rather than to the dashboard" do
    sign_in_page = new_user_session_path # before the request, for the same reason as above

    get mission_control_jobs_path

    assert_redirected_to sign_in_page
  end
end
