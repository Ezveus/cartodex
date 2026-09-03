require "test_helper"

# `/admin/jobs` mounts the MissionControl::Jobs engine, and it is the one page of the app whose
# markup lives inside somebody else's gem: `app/views/layouts/mission_control/jobs/`
# `_application_selection.html.erb` overrides the engine's own partial. Nothing in the suite had
# ever loaded that page, so a bump renaming what the override borrows would have shipped a 500 past
# a green CI (the 1.1.0 → 1.2.0 bump rewrote that very partial upstream).
#
# Read what the first test covers narrowly, because two things it looks like it covers, it does not.
# It exercises the `application_selection/servers` sub-partial, the `selectable_applications` helper
# and the `main_app.` prefix on the "Back to admin" link — that prefix being the one piece here that
# degrades silently instead of raising. It does **not** reach the other sub-partial,
# `application_selection/applications`: the override renders that one only
# `if selectable_applications.any?`, and this app registers a single application, so the template is
# never resolved. Neither is it resolved in production, for the same reason — a rename there breaks
# nothing until a second application is configured, and then it breaks both at once.
#
# Nor does any of this pin the SolidQueue half of the dashboard: the test environment sets no
# `active_job.queue_adapter`, so the engine registers `:async` and renders neither the Workers nor
# the Recurring tasks section. What is pinned is the layout, the override, and the gate below.
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
    assert back, "no \"Back to admin\" link: either the override did not render, or the engine " \
                 "stopped rendering application_selection at all"
    # Compare paths, not hrefs: the engine appends its own server_id to everything it generates.
    assert_equal admin_root, URI.parse(back["href"]).path
  end

  test "the admin panel carries the link that gets you there" do
    sign_in @admin

    get admin_root_path

    # The other leg of the round trip. Ui::AdminNavbar is what makes the page reachable at all, and
    # its "Jobs" link is followed by nothing else in the suite — admin_navigation_test.rb clicks its
    # way around the panel without ever leaving it.
    assert_select "a[href=?]", mission_control_jobs_path, text: "Jobs"
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
