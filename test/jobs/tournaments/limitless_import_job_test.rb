require "test_helper"

class Tournaments::LimitlessImportJobTest < ActiveJob::TestCase
  RESULTS_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_deck_results.html")).freeze
  DECKLIST_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_decklist.html")).freeze
  # The fixture holds seven rows across four events; the 2024 one has no Standard pool, so six
  # rows are importable.
  IMPORTABLE = 6

  setup do
    @admin = users(:one)
    @archetype = archetypes(:standings_marker)
    @import = @admin.imports.create!(kind: "limitless_standings", label: "Raging Bolt — Limitless deck 280")
    @original_http = HttpFetcher.method(:call)
    @original_cards_fetcher = Cards::Fetcher.method(:call)
    @original_pause = Tournaments::LimitlessImportJob.request_pause
    @original_failure_limit = Tournaments::LimitlessImportJob.failure_limit
    Tournaments::LimitlessImportJob.request_pause = 0
    stub_http
    stub_cards_fetcher
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http)
    Cards::Fetcher.define_singleton_method(:call, @original_cards_fetcher)
    Tournaments::LimitlessImportJob.request_pause = @original_pause
    Tournaments::LimitlessImportJob.failure_limit = @original_failure_limit
  end

  test "imports the plan and records what it created" do
    assert_difference -> { TournamentStanding.count }, IMPORTABLE do
      perform
    end

    @import.reload
    assert_equal "completed", @import.status
    assert_nil @import.error_message
    # The ids are the whole undo story: nothing else in the app can find the rows a run wrote, and
    # an event becomes undeletable the moment a member records a participation at it.
    assert_equal IMPORTABLE, @import.created_standing_ids.size
    assert_equal IMPORTABLE, TournamentStanding.where(id: @import.created_standing_ids).count
  end

  # The one message an admin actually reads is the flash this broadcasts. The fixture's 2024 event
  # predates every seeded Standard pool, so one row is blocked — and a run that silently skipped a
  # whole event while reporting only its successes would leave the admin believing it was complete.
  test "tells the admin what the run did, blocked rows included" do
    message = broadcast_flash { perform }

    assert_match(/#{IMPORTABLE} created/, message)
    assert_match(/1 in events that cannot be imported/, message)
    assert_match(/Raging Bolt/, message)
  end

  test "folds the JR and SR headings into one catalogued event" do
    perform

    naic = Tournament.find_by(name_normalized: "naic 2026, new orleans")
    assert_equal Date.new(2026, 6, 10), naic.date
    assert_equal({ "masters" => 2, "senior" => 1, "junior" => 1 }, naic.standings.group(:division).count)
  end

  # The admin approved a plan they were shown, and this job rebuilds it from a page that may have
  # changed since — Limitless publishes a new event the day it happens. Without this check a stale
  # browser tab silently imports rows nobody ever looked at.
  test "refuses a plan that no longer matches the one previewed" do
    assert_no_difference -> { TournamentStanding.count } do
      perform(expected_row_count: IMPORTABLE - 1)
    end

    @import.reload
    assert_equal "failed", @import.status
    assert_match(/not the #{IMPORTABLE - 1} that were previewed/, @import.error_message)
  end

  test "refuses a plan over the ceiling" do
    assert_no_difference -> { TournamentStanding.count } do
      perform(max_rows: 2, expected_row_count: nil)
    end

    assert_equal "failed", @import.reload.status
    assert_match(/over the 2 allowed/, @import.error_message)
  end

  test "fails the import when the archetype has been deleted" do
    perform(archetype_id: 0)

    assert_equal "failed", @import.reload.status
    assert_match(/archetype was deleted/, @import.error_message)
  end

  test "fails the import when the results page cannot be read" do
    HttpFetcher.define_singleton_method(:call) { |_url| raise HttpFetcher::FetchError, "HTTP 503" }

    perform

    assert_equal "failed", @import.reload.status
    assert_match(/HTTP 503/, @import.error_message)
  end

  # A run that wrote forty rows and refused three is a success with a note, and the note has to
  # survive into the admin table — the only place anybody will look for it. A decklist that will
  # not parse is also not "the far side is down", so it must not count toward the
  # consecutive-failure abort: five of them in a row still leave the run completed.
  test "completes with the refused rows named in the error message" do
    stub_http(decklist: ->(_url) { raise Tournaments::LimitlessDecklist::ParseError, "parsed to 59 cards, not 60" })

    perform

    @import.reload
    assert_equal "completed", @import.status
    # Five, not six: one of the importable rows names a player with no public list, which is not a
    # failure — 21 of the 1569 rows on the real page are like that.
    assert_match(/5 rows refused/, @import.error_message)
    assert_match(/parsed to 59 cards/, @import.error_message)
    # The standings still landed — a placement and an archetype is a record even with no list.
    assert_equal IMPORTABLE, @import.created_standing_ids.size
  end

  # A run the far side stopped answering is not a success with a note: the rows it did not reach
  # were never even attempted, and reporting that as "completed" would tell an admin the import is
  # done when half of it is missing.
  test "fails the import when the run gave up on a silent remote" do
    # Two, because the fixture's six importable rows include one with no decklist to fetch: that
    # row succeeds and clears the count, so five consecutive failures never occur through it.
    Tournaments::LimitlessImportJob.failure_limit = 2
    stub_http(decklist: ->(_url) { raise HttpFetcher::FetchError, "HTTP 429" })

    perform

    @import.reload
    assert_equal "failed", @import.status
    assert_match(/consecutive fetch failures/, @import.error_message)
    # What it did manage to write is still recorded, so undo can take it back.
    assert_predicate @import.created_standing_ids, :any?
  end

  # Enqueued with ids, so an Import deleted from the admin panel mid-flight is an ordinary lookup
  # miss rather than an ActiveJob::DeserializationError raised before #perform is even entered.
  test "does nothing when the import row is gone" do
    id = @import.id
    @import.destroy!

    assert_no_difference -> { TournamentStanding.count } do
      Tournaments::LimitlessImportJob.perform_now(id, @admin.id, options)
    end
  end

  private

  # The job's own report, as the admin receives it: appended to their notifications stream, never
  # returned. Asserting on the Import row alone would miss the sentence entirely.
  def broadcast_flash
    original = Turbo::StreamsChannel.method(:broadcast_append_to)
    captured = []
    Turbo::StreamsChannel.define_singleton_method(:broadcast_append_to) { |*_args, **kwargs|
      captured << kwargs[:html]
    }
    yield
    captured.join
  ensure
    Turbo::StreamsChannel.define_singleton_method(:broadcast_append_to, original)
  end

  def perform(**overrides)
    Tournaments::LimitlessImportJob.perform_now(@import.id, @admin.id, options(**overrides))
  end

  def options(**overrides)
    {
      "deck_id" => "280", "archetype_id" => @archetype.id,
      "event_filters" => [], "limit_per_event" => nil, "expected_row_count" => IMPORTABLE
    }.merge(overrides.transform_keys(&:to_s))
  end

  def stub_http(decklist: nil)
    HttpFetcher.define_singleton_method(:call) { |url|
      next RESULTS_HTML if url.include?("/results")
      next decklist.call(url) if decklist

      DECKLIST_HTML
    }
  end

  def stub_cards_fetcher
    Cards::Fetcher.define_singleton_method(:call) { |url|
      segments = URI.parse(url).path.split("/")
      Card.find_or_create_by!(set_name: segments[2], set_number: segments[3]) do |card|
        card.name = "Card #{segments[2]} #{segments[3]}"
        card.card_type = "Trainer"
        card.rarity = "Common"
      end
    }
  end
end
