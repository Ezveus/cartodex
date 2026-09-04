# Run one admin "import a tournament's field from Limitless" against an Import row.
#
# Enqueued with ids rather than records, for the reason Tournaments::StandingListImportJob is: an
# Import can be deleted from the admin panel while the run is in flight, and a record handed to a
# job that no longer exists raises ActiveRecord::DeserializationError *before* #perform is entered,
# where this method's own rescue cannot see it — leaving the row at "pending" forever.
class Tournaments::LimitlessImportJob < ApplicationJob
  class PlanDrifted < StandardError; end
  class PlanTooLarge < StandardError; end
  class ArchetypeMissing < StandardError; end

  queue_as :default

  # Half a second between decklist pages. A run is hundreds of requests to somebody else's site in
  # a tight loop; nothing else this app does asks Limitless for that much at once. A class
  # attribute rather than a constant so a test can set it to zero: there is no remote to be polite
  # to in a test, and eight rows would otherwise cost four seconds of sleeping.
  class_attribute :request_pause, default: 0.5
  # Enough failures to be worth naming, few enough to stay readable in the admin table's
  # disclosure. The count is always stated, so a truncated list never hides how bad it was.
  FAILURES_LISTED = 20

  def perform(import_id, user_id, options = {})
    options = options.with_indifferent_access
    import = Import.find_by(id: import_id)
    user = User.find_by(id: user_id)
    return if import.nil? || user.nil?

    archetype = Archetype.find_by(id: options[:archetype_id])
    raise ArchetypeMissing, "the archetype was deleted before the import ran" if archetype.nil?

    plan = build_plan(options)
    verify!(plan, options[:expected_row_count])

    finish(import, user, Tournaments::StandingsImporter.call(
      plan: plan, archetype: archetype, user: user, pause: request_pause
    ))
  rescue StandardError => e
    report_failure(import, user, e)
  end

  private

  def build_plan(options)
    rows = Tournaments::LimitlessResults.call(options[:deck_id])
    Tournaments::StandingsImportPlan.call(
      rows: rows,
      event_filters: Array(options[:event_filters]),
      limit_per_event: options[:limit_per_event],
      # Only ever passed by a test: the ceiling exists to stop an admin importing 1569 rows by
      # accident, and proving it works should not need a 300-row HTML fixture.
      **({ max_rows: options[:max_rows].to_i } if options[:max_rows].present?).to_h
    )
  end

  # The admin approved a plan they were shown, and this job rebuilds it from a page that may have
  # changed since — Limitless publishes a new event the day it happens. Re-fetching is what keeps
  # a stale browser tab from replaying an old plan; refusing a plan that no longer matches is what
  # keeps the re-fetch from importing rows nobody ever saw.
  def verify!(plan, expected_row_count)
    raise PlanTooLarge, "the plan covers #{plan.importable_rows.size} rows, over the #{plan.max_rows} allowed" if
      plan.over_limit?

    expected = expected_row_count.presence&.to_i
    return if expected.nil? || expected == plan.importable_rows.size

    raise PlanDrifted,
      "Limitless now offers #{plan.importable_rows.size} importable rows, not the #{expected} that were previewed — " \
      "preview it again"
  end

  # A run that imported forty rows and refused three is a success with a note, not a failure: the
  # forty are written and undoing them is a button away. Only a run that could do nothing at all —
  # or that gave up because the far side stopped answering — is failed.
  def finish(import, user, result)
    import.update!(
      status: result.aborted? ? "failed" : "completed",
      created_standing_ids: result.standing_ids,
      error_message: summarise(result)
    )
    broadcast(user, result.aborted? ? "flash-alert" : "flash-notice", outcome(import, result))
  end

  def outcome(import, result)
    counts = "#{result.created} created, #{result.enriched} enriched, #{result.skipped} already present"
    return %(Import of "#{import.label}" stopped: #{result.aborted_reason} (#{counts}).) if result.aborted?

    %(Import of "#{import.label}" finished: #{counts}#{", #{result.failed_count} refused" if result.failed_count.positive?}.)
  end

  def summarise(result)
    lines = []
    lines << result.aborted_reason if result.aborted?
    if result.failures.any?
      lines << "#{result.failures.size} #{"row".pluralize(result.failures.size)} refused:"
      lines.concat(result.failures.first(FAILURES_LISTED).map { |label, message| "  #{label}: #{message}" })
      lines << "  … and #{result.failures.size - FAILURES_LISTED} more" if result.failures.size > FAILURES_LISTED
    end
    lines.join("\n").presence
  end

  def report_failure(import, user, error)
    return if import.nil?

    import.update!(status: "failed", error_message: error.message)
    broadcast(user, "flash-alert", %(Import of "#{import.label}" failed: #{error.message}))
  end

  def broadcast(user, css_class, message)
    Turbo::StreamsChannel.broadcast_append_to(
      user, :notifications,
      target: "flash-messages",
      html: %(<div class="flash #{css_class}">#{ERB::Util.html_escape(message)}</div>)
    )
  rescue StandardError => e
    # A failed broadcast must not rewrite a successful import: the work is the standings, the
    # broadcast is only a notification about them.
    Rails.logger.error("Tournaments::LimitlessImportJob: broadcast failed: #{e.message}")
  end
end
