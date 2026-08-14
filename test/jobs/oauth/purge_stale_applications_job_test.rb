require "test_helper"

module Oauth
  class PurgeStaleApplicationsJobTest < ActiveJob::TestCase
    def application(created_at:)
      Doorkeeper::Application.create!(
        name: "Client",
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        scopes: "mcp:read"
      ).tap { |a| a.update_column(:created_at, created_at) }
    end

    test "deletes an old application that was never used" do
      stale = application(created_at: 8.days.ago)

      PurgeStaleApplicationsJob.perform_now

      assert_not Doorkeeper::Application.exists?(stale.id)
    end

    test "keeps a recent application that has not been used yet" do
      # Registration and authorization are separate round-trips; a client that
      # registered a minute ago has not had the chance to be authorized.
      fresh = application(created_at: 1.hour.ago)

      PurgeStaleApplicationsJob.perform_now

      assert Doorkeeper::Application.exists?(fresh.id)
    end

    test "keeps an old application that holds an access token" do
      used = application(created_at: 30.days.ago)
      Doorkeeper::AccessToken.create!(
        application: used, resource_owner_id: users(:one).id, scopes: "mcp:read"
      )

      PurgeStaleApplicationsJob.perform_now

      assert Doorkeeper::Application.exists?(used.id)
    end

    test "keeps an old application that holds an access grant" do
      used = application(created_at: 30.days.ago)
      Doorkeeper::AccessGrant.create!(
        application: used, resource_owner_id: users(:one).id, scopes: "mcp:read",
        redirect_uri: used.redirect_uri, expires_in: 600
      )

      PurgeStaleApplicationsJob.perform_now

      assert Doorkeeper::Application.exists?(used.id)
    end

    test "includes the grace period boundary in deletions (inclusive range)" do
      # The grace period uses an inclusive range (..GRACE_PERIOD.ago).
      # An application created exactly at the boundary should be deleted.
      # We use a fixed time to avoid floating-point precision issues.
      grace_period = PurgeStaleApplicationsJob::GRACE_PERIOD

      # Create the boundary time with whole-second precision
      boundary_now = Time.at(1786118400)  # Fixed timestamp
      boundary_time = boundary_now - grace_period  # Exactly 7 days earlier

      boundary = application(created_at: boundary_time)

      # Run the job at the recorded moment
      travel_to(boundary_now) do
        PurgeStaleApplicationsJob.perform_now
      end

      assert_not Doorkeeper::Application.exists?(boundary.id)
    end
  end
end
