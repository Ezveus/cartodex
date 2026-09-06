require "test_helper"

# The other half of test/controllers/public_access_test.rb. That file is a hand-written list of the
# actions a visitor may reach; this one asks the opposite question of every route in the admin
# namespace at once, and it exists because a new admin screen inherits **nothing**.
#
# Measured before it was written: a controller declared `< ApplicationController` instead of
# `< Admin::BaseController`, routed under /admin and reachable by any signed-in member, left the
# whole suite green — 1422 runs, 0 failures. Nothing in the suite enumerated admin routes, and the
# per-controller tests are each soldered to their own path, so none of their coverage transfers.
#
# It walks the routing table rather than naming paths, so a screen added tomorrow is covered the
# day it is routed and not the day somebody remembers to add a case.
class AdminGateTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Every dynamic segment becomes "1". The gate is a before_action, so it answers before any
  # lookup: whether the id exists decides nothing here, and a route that 404s for an admin still
  # redirects a member.
  def self.admin_routes
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      next unless controller&.start_with?("admin/")

      verb = route.verb.presence || "GET"
      path = route.path.spec.to_s.sub("(.:format)", "").gsub(/:[a-z_]+/, "1")
      [ verb, path ]
    end.uniq
  end

  test "every admin route refuses a member who is not an admin" do
    routes = self.class.admin_routes

    assert_operator routes.size, :>, 20, "the routing table gave up fewer admin routes than exist"

    sign_in users(:two)

    routes.each do |verb, path|
      process(verb.downcase.to_sym, path)

      # Asserted before the destination, so an action that simply answers a member reads as
      # "did not refuse" rather than as a NoMethodError on a nil location.
      assert_response :redirect, "#{verb} #{path} answered a non-admin instead of refusing them"
      assert_redirected_to root_path, "#{verb} #{path} refused a non-admin somewhere unexpected"
    end
  end

  test "every admin route refuses a visitor with no session" do
    self.class.admin_routes.each do |verb, path|
      process(verb.downcase.to_sym, path)

      assert_response :redirect, "#{verb} #{path} answered a visitor without redirecting"
      assert_match(/sign_in|\A#{Regexp.escape(root_url)}\z/, response.location,
                   "#{verb} #{path} sent a visitor somewhere other than sign-in")
    end
  end
end
