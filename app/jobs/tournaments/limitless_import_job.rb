# Run one admin "import a tournament's field from Limitless" against an Import row.
#
# One job for all three sources, and `options["source"]` is the whole of the difference: "online"
# reads play.limitlesstcg.com's best-finishes leaderboard through Tournaments::OnlineResults and
# its decklists through Tournaments::OnlineDecklist; "event" reads one whole real-world event —
# every division — through Tournaments::LimitlessEventResults and its lists through
# Tournaments::EventDecklists, which is one bulk page per division rather than one page per row;
# anything else (including the absence of the key, which is what a run enqueued before this
# existed carries) reads the paper results page.
#
# The event source is the only one whose rows do not share an archetype, so it carries none at
# all: each row takes the archetype LimitlessArchetypeMapping answers for its Limitless deck, and
# a deck nobody has confirmed blocks its rows by name rather than being guessed at.
#
# Import::KINDS gains nothing for it. An `online_standings` kind is the obvious move and a trap:
# Tournaments::StandingsImportUndo raises unless the kind is "limitless_standings" and
# Admin::ImportsController#undo gates on the same literal, so a new kind would produce runs that
# look identical in the admin table and silently cannot be undone. Both sources leave the same
# receipt and undo does the same work on both; the Import's *label* is what says where a run came
# from.
#
# Enqueued with ids rather than records, for the reason Tournaments::StandingListImportJob is: an
# Import can be deleted from the admin panel while the run is in flight, and a record handed to a
# job that no longer exists raises ActiveRecord::DeserializationError *before* #perform is entered,
# where this method's own rescue cannot see it — leaving the row at "pending" forever.
class Tournaments::LimitlessImportJob < ApplicationJob
  class PlanDrifted < StandardError; end
  class PlanTooLarge < StandardError; end
  class ArchetypeMissing < StandardError; end
  class PoolUnresolvable < StandardError; end

  # The online leaderboard is read per card pool, and a pool is a Standard one: the whole reason
  # the `set` parameter can anchor a run is that it names the newest set of a Standard pool. It is
  # not a form field, so it is not user input and needs no guard beyond being this literal.
  ONLINE_FORMAT = "standard".freeze
  ONLINE_SOURCE = "online".freeze
  # The third source: one whole real-world event, every division, off
  # limitlesstcg.com/tournaments/<id>. Absence still reads as paper, so a run enqueued before this
  # existed is still the run its admin approved.
  EVENT_SOURCE = "event".freeze

  # StandingsImportPlan::DEFAULT_MAX_ROWS is 300 to stop an archetype-history run walking 176
  # events and 1569 rows. One event is a bounded thing whose size the admin has just read in the
  # preview — and the largest Limitless lists is 3752 players — so the ceiling is raised for this
  # source alone rather than for the plan.
  EVENT_MAX_ROWS = 1000

  queue_as :default

  # Half a second between decklist pages. A run is hundreds of requests to somebody else's site in
  # a tight loop; nothing else this app does asks Limitless for that much at once. A class
  # attribute rather than a constant so a test can set it to zero: there is no remote to be polite
  # to in a test, and eight rows would otherwise cost four seconds of sleeping.
  class_attribute :request_pause, default: 0.5
  # Likewise a class attribute rather than the service's constant: the test fixture holds six rows,
  # one of which carries no decklist and therefore succeeds, so five *consecutive* failing rows are
  # not reachable through it — and proving that an abandoned run is reported as failed matters more
  # than proving it at exactly five.
  class_attribute :failure_limit, default: Tournaments::StandingsImporter::CONSECUTIVE_FAILURE_LIMIT
  # Enough failures to be worth naming, few enough to stay readable in the admin table's
  # disclosure. The count is always stated, so a truncated list never hides how bad it was.
  FAILURES_LISTED = 20

  # The online leaderboard names its card pool in the URL's `set` parameter, and that — never the
  # event's date — is what anchors every row a run writes: StandardPool.at reads `legal_on`, which
  # online play runs up to two weeks ahead of. Measured: 3 of the 20 rows of one PBL leaderboard
  # predate TEF-PBL's legal_on, so anchoring by date files them under the previous pool, in a
  # sample whose other lists could not legally hold their cards.
  #
  # Exactly one pool, or the run is refused. `.first` would be wrong: the UNIQUE key is the *pair*
  # of bounds, so two pools may legitimately share a last set — which is what a rotation landing
  # between two set releases produces, moving the first bound while the last stays put. Today's
  # pools happen to have distinct last sets, so a coin toss would look correct right up until it
  # silently was not.
  #
  # A class method because Admin::StandingsImportsController resolves the same set before it
  # fetches anything, and the screen's refusal and the run's have to be the same answer in the
  # same sentence. The run resolves it again rather than being handed a pool id, because it
  # re-derives the whole plan rather than trusting what the browser carried back.
  def self.standard_pool_for(set)
    pools = StandardPool.joins(:last_card_set).where(card_sets: { code: set.to_s }).to_a
    return pools.first if pools.one?

    if pools.empty?
      raise PoolUnresolvable, "No Standard pool ends at #{set} — that set is what anchors every row " \
        "this writes. Add the pool from Admin → Standard pools, or name a set that has one."
    end

    raise PoolUnresolvable, "#{pools.size} Standard pools end at #{set} (#{pools.map(&:name).to_sentence}) — " \
      "a pool is its pair of bounds, so the set alone cannot say which of them this leaderboard is."
  end

  # An event page states its card pool as a *pair* of bounds — "TEF-PBL", which is
  # StandardPool#name byte for byte — where the leaderboard states one set, so this is the other
  # half of standard_pool_for and not a refinement of it. The pair is the pool's UNIQUE key, so
  # the ambiguity that method has to refuse cannot arise here.
  #
  # Matched in Ruby over every pool rather than by joining card_sets twice: the table holds a
  # handful of rows, `name` is already the thing published, and a hand-aliased double join is a
  # query that breaks at runtime the day either association is renamed.
  #
  # nil rather than a raise, deliberately: the plan blocks the event and names the code it could
  # not resolve, which is one sentence the screen and the run already share.
  def self.standard_pool_named(name)
    return if name.blank?

    StandardPool.named.find { |pool| pool.name == name.to_s }
  end

  # The pool the event's own pages publish. Most common rather than first, the rule
  # StandingsImportPlan#dominant_format follows: no event mixes two, and a stray icon must not
  # decide an event's anchor on its own.
  def self.published_pool_for(rows)
    code = rows.filter_map { |row| row.format.presence }.tally.max_by { |_code, count| count }&.first

    standard_pool_named(code)
  end

  # One run, one event, and this is the source's id for it. Spelled once because the screen writes
  # it on a create and the run re-derives it to find that same event again after a rename.
  def self.event_key_for(tournament_id) = "limitless-event:#{tournament_id}"

  def perform(import_id, user_id, options = {})
    options = options.with_indifferent_access
    import = Import.find_by(id: import_id)
    user = User.find_by(id: user_id)
    return if import.nil? || user.nil?

    archetype = Archetype.find_by(id: options[:archetype_id])
    # Source-conditional, because an event's sheet holds 45 distinct decks and no run archetype
    # could be true of all of them: there each row carries its own, resolved through
    # LimitlessArchetypeMapping, and a row nobody has mapped is blocked by name. The two older
    # sources still declare one for the whole run and are still refused without it.
    raise ArchetypeMissing, "the archetype was deleted before the import ran" if archetype.nil? && !event?(options)

    plan = build_plan(options)
    verify!(plan, options[:expected_row_count])

    finish(import, user, Tournaments::StandingsImporter.call(
      plan: plan, archetype: archetype, user: user,
      # The two couplings that differ between the sources, and they travel together: the online
      # decklist page is a different layout *and* one player enters one list into six weekly
      # tournaments, so its rows are de-duplicated per (player slug, list content) while a paper
      # field's are not.
      decklist_service: decklist_service(options), deduplicate: online?(options),
      pause: request_pause, failure_limit: failure_limit
    ))
  rescue StandardError => e
    report_failure(import, user, e)
  end

  private

  def build_plan(options)
    # Read before the plan is built rather than inline, because the event source states its card
    # pool on its own pages: the anchor is a fact about the rows, not about the form.
    rows = source_rows(options)

    Tournaments::StandingsImportPlan.call(
      rows: rows,
      event_filters: Array(options[:event_filters]),
      limit_per_event: options[:limit_per_event],
      # What the rows cannot say and the caller knows: an online run is anchored by its
      # leaderboard's `set`, and its arbitrary event names must never be read for a tier.
      online: online?(options),
      standard_pool: standard_pool(options, rows),
      # One run, one event. The plan reads this as "every row here belongs to one real-world
      # event, and this is the source's id for it" — see StandingsImportPlan#initialize.
      event_key: (self.class.event_key_for(options[:tournament_id]) if event?(options)),
      **max_rows(options)
    )
  end

  # Absence is paper: a run enqueued before this job knew about a second source carries no key at
  # all, and must still be the run its admin approved.
  def online?(options) = options[:source].to_s == ONLINE_SOURCE
  def event?(options) = options[:source].to_s == EVENT_SOURCE

  def standard_pool(options, rows)
    return self.class.standard_pool_for(options[:set]) if online?(options)
    return self.class.published_pool_for(rows) if event?(options)

    nil
  end

  def max_rows(options)
    # Only ever passed by a test: the ceiling exists to stop an admin importing 1569 rows by
    # accident, and proving it works should not need a 300-row HTML fixture.
    return { max_rows: options[:max_rows].to_i } if options[:max_rows].present?
    return { max_rows: EVENT_MAX_ROWS } if event?(options)

    {}
  end

  def source_rows(options)
    return Tournaments::LimitlessEventResults.call(options[:tournament_id]) if event?(options)
    return Tournaments::LimitlessResults.call(options[:deck_id]) unless online?(options)

    Tournaments::OnlineResults.call(options[:slug], format: ONLINE_FORMAT,
      rotation: options[:rotation], set: options[:set])
  end

  # An instance and not a class for the event source, and that is the whole of why a whole event
  # costs six requests: EventDecklists holds one parsed bulk page per division and answers every
  # row of it, where the two older services fetch one page per row.
  def decklist_service(options)
    return Tournaments::EventDecklists.new(options[:tournament_id]) if event?(options)

    online?(options) ? Tournaments::OnlineDecklist : Tournaments::LimitlessDecklist
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
      enriched_standing_ids: result.enriched_standing_ids,
      error_message: summarise(result)
    )
    broadcast(user, result.aborted? ? "flash-alert" : "flash-notice", outcome(import, result))
  end

  def outcome(import, result)
    counts = "#{result.created} created, #{result.enriched} enriched, #{result.skipped} already present"
    # Named only when there were any: a run with nothing blocked should not have to explain a zero,
    # and a run that quietly skipped a whole event must not look like one that had nothing to skip.
    #
    # The duplicate count is the same rule and matters more: an online run reads twenty rows and
    # writes thirteen, and a report naming only the thirteen leaves the admin looking for the seven
    # it lost. It is always zero for a paper run, which does not de-duplicate at all.
    counts += ", #{result.duplicates} dropped as duplicates" if result.duplicates.positive?
    counts += ", #{result.blocked} refused before writing" if result.blocked.positive?
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
    # The rows the run declined to write, by reason. The flash is transient and names a number; the
    # Import row is the only permanent record of a run, and without this an event source refusing 48
    # rows for one unconfirmed deck left nothing anywhere saying which deck — so the admin who came
    # back to finish the job had only the preview to go back to. Grouped, because 48 rows of one
    # event share one sentence.
    if result.blocked_reasons.present?
      lines << "#{result.blocked} #{"row".pluralize(result.blocked)} not written:"
      lines.concat(result.blocked_reasons.sort_by { |_reason, count| -count }.first(FAILURES_LISTED)
        .map { |reason, count| "  #{count} x #{reason}" })
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
