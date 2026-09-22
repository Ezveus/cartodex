module Admin
  # "Import an archetype's field from Limitless" — the one screen this feature has, now reading
  # any of three sources: the paper events at limitlesstcg.com/decks/<id>/results, the online best
  # finishes at play.limitlesstcg.com/decks/<slug>, and one whole real-world event at
  # limitlesstcg.com/tournaments/<id>.
  #
  # The third source is the one that changes the screen rather than only its fields. Its rows do
  # not share an archetype — 45 distinct decks over 575 rows on the measured event — so the
  # preview gains a line per *distinct deck reference*, never one per row, carrying the proposal
  # Tournaments::ArchetypeProposer makes from one representative list and a select the admin may
  # override. `create` persists what they confirmed and then enqueues; the plan reads
  # LimitlessArchetypeMapping itself, so nothing about archetypes travels in the job's arguments.
  # A reference left blank is not a guess — its rows plan as :blocked and the run reports them.
  #
  # No Pundit call anywhere below: Admin::BaseController#require_admin! is the whole gate for this
  # namespace, and an `authorize` here would be the only one in the panel.
  #
  # The screen is deliberately two requests. `preview` reads the source once and renders what a run
  # *would* write — which event each row lands in, the derived tier, format and division, what is
  # already there — because everything this writes goes into a public catalog that no member can
  # tell an import from a hand-typed row in. `create` is the click that follows.
  class StandingsImportsController < BaseController
    # The Limitless deck id is interpolated into a URL that is then fetched, so it is narrowed
    # here, before it can reach one. HttpFetcher refuses a non-HTTP URI as a backstop, but a
    # backstop is not the same as the caller saying what it will interpolate — and this is the
    # only place that can refuse while there is still a form to send the admin back to.
    DECK_ID_RE = /\A\d+\z/

    # The online source interpolates three values where the paper one interpolates a number, so it
    # gets three guards of the same narrowness. Borrowed from the service rather than re-spelled:
    # Tournaments::OnlineResults validates the very same values and raises ArgumentError from its
    # constructor — which, by the time it reaches a browser, is the 500 the rescue below exists to
    # prevent. Two copies of a pattern would also drift, and the loose half would be this one.
    SLUG_RE = Tournaments::OnlineResults::SLUG_RE
    ROTATION_RE = Tournaments::OnlineResults::ROTATION_RE
    SET_RE = Tournaments::OnlineResults::SET_RE

    # Borrowed, not re-spelled, like the three regexes above it: this string is the contract
    # between the form, the POST and the job, and two copies of it drift silently — the screen
    # would go on enqueuing "online" runs that the job read as paper.
    ONLINE_SOURCE = Tournaments::LimitlessImportJob::ONLINE_SOURCE
    EVENT_SOURCE = Tournaments::LimitlessImportJob::EVENT_SOURCE
    DEFAULT_SOURCE = "paper".freeze
    SOURCES = [ DEFAULT_SOURCE, ONLINE_SOURCE, EVENT_SOURCE ].freeze

    # Borrowed from the service for the reason the three online patterns are: the tournament id is
    # interpolated into three URLs this fetches, and refusing it here is the only refusal that
    # still has a form to send the admin back to.
    TOURNAMENT_ID_RE = Tournaments::LimitlessEventResults::ID_RE

    # One line of the arbitration screen: a Limitless deck as the event's pages name it, and what
    # cartodex has to say about it. `confirmed` is a stored answer an admin gave once — such a
    # reference is never proposed for again, which is what makes the second event cheap.
    # `proposal` is a machine's opinion with its reason attached, `error` the honest alternative
    # when the event published no list to read the deck from.
    MappingLine = Struct.new(:reference, :label, :confirmed, :proposal, :error, keyword_init: true) do
      def selected_archetype = confirmed || proposal&.archetype
      def verdict = confirmed ? :confirmed : proposal&.verdict
    end

    before_action :read_form_params
    # Only where a form is rendered: `create` answers with a redirect either way, and the select
    # would be a query spent on a page nobody sees.
    before_action :load_archetypes, only: %i[new preview]

    def new; end

    # A GET. See the routes file for why it cannot be the POST it looks like.
    def preview
      message = refusal("Pick the archetype every imported row will carry.")
      return refuse(message) if message

      rows = source_rows
      # Before the plan, because the plan reads the store and the lines are what fills it — and
      # because the lines are the more expensive half: one list per unmapped deck, never one per
      # row.
      @mapping_lines = mapping_lines(rows) if event?

      @plan = Tournaments::StandingsImportPlan.call(
        rows: rows, event_filters: @event_filters, limit_per_event: @limit_per_event,
        **classification(rows)
      )
      render :new
    rescue Tournaments::LimitlessResults::ParseError, Tournaments::OnlineResults::ParseError,
      Tournaments::LimitlessEventResults::ParseError, Tournaments::EventDecklists::ParseError,
      HttpFetcher::FetchError => e
      # Every one of them is reachable from one wrong value in a text field — a deck id, a slug or
      # a tournament id nobody has published, a rotation and set naming an empty leaderboard, a
      # page whose layout moved, a rate limit. Re-rendering the form with the reason is the only
      # answer that leaves the admin somewhere to go; a 500 is not. Each source's ParseError is
      # named because each is a *different constant* — a source switch that rescued only the paper
      # one would answer a mistyped id with that 500.
      refuse("Could not read #{source_label}: #{e.message}")
    end

    def create
      # Re-validated rather than trusted: the confirm form carries these back through the browser,
      # which makes them ordinary user input again however carefully the preview checked them.
      message = refusal("That archetype no longer exists — pick one and preview again.")
      return redirect_to(new_admin_standings_import_path, alert: message) if message

      # Before the Import row, because the plan the run builds reads the store: an enqueue that
      # beat the write would import an event every one of whose rows is blocked.
      persist_mappings if event?

      import = current_user.imports.create!(kind: "limitless_standings", label: import_label)
      Tournaments::LimitlessImportJob.perform_later(import.id, current_user.id, job_options)

      redirect_to admin_imports_path,
        notice: "Importing #{import_label}. Watch this table for the result."
    end

    # "Undo this run". `params[:id]` is an *Import* id: the run left its receipt there
    # (imports.created_standing_ids) and there is no standings-import record to address.
    private

    def read_form_params
      # An allowlist rather than a ternary now that there are three: an unknown value reads as
      # paper, which is also what a run enqueued before this screen knew about a second source
      # carries.
      @source = SOURCES.include?(params[:source].to_s) ? params[:source].to_s : DEFAULT_SOURCE
      @tournament_id = params[:tournament_id].to_s.strip
      @deck_id = params[:deck_id].to_s.strip
      @slug = params[:slug].to_s.strip
      @rotation = params[:rotation].to_s.strip
      @set = params[:set].to_s.strip
      @archetype_id = params[:archetype_id].presence&.to_i
      @archetype = Archetype.find_by(id: @archetype_id)
      @event_filters_text = params[:event_filters].to_s
      @event_filters = parse_filters(@event_filters_text)
      @limit_per_event_text = params[:limit_per_event].to_s.strip
      @limit_per_event = @limit_per_event_text.presence&.to_i
    end

    def load_archetypes
      @archetypes = Archetype.order(:name)
    end

    def online? = @source == ONLINE_SOURCE
    def event? = @source == EVENT_SOURCE

    # One filter per line *or* comma-separated, because both are how a list of event names gets
    # typed: pasted off a schedule it arrives one per line, written by hand it arrives with commas.
    def parse_filters(text)
      text.split(/[\n,]/).map(&:strip).reject(&:empty?)
    end

    def refuse(message)
      flash.now[:alert] = message
      render :new
    end

    # The whole refusal, in the order the values are used: what is interpolated into a URL is
    # refused before the archetype, which is refused before a pool is looked up — and every one of
    # them before anything is fetched.
    def refusal(archetype_message)
      source_refusal || (archetype_message if archetype_required? && @archetype.nil?) || pool_refusal
    end

    # Source-conditional, and that is the rule rather than a relaxation. The two older sources
    # each *are* one archetype — a deck-results page, a deck's leaderboard — and every row they
    # write carries the one the admin declared. An event's sheet holds 45 distinct decks, so no
    # declaration could be true of all of them: the arbitration is per deck, stored, and the run
    # carries none. Relaxed for all three, #create reaches import_label's @archetype.name and 500s.
    def archetype_required? = !event?

    def source_refusal
      return tournament_id_refusal if event?
      return deck_id_refusal unless online?

      unless SLUG_RE.match?(@slug)
        return "The leaderboard slug must be lowercase letters, digits and dashes — it is " \
          "interpolated into the URL this fetches."
      end
      unless ROTATION_RE.match?(@rotation)
        return "The rotation must be a four-digit year — it is interpolated into the URL this fetches."
      end
      return if SET_RE.match?(@set)

      "The set must be a short uppercase set code such as PBL — it is interpolated into the URL this fetches."
    end

    def deck_id_refusal
      return if @deck_id.match?(DECK_ID_RE)

      "The Limitless deck id must be a number — it is interpolated into the URL this fetches."
    end

    # Three URLs per run, and the decklists pages besides. Both services refuse it too and raise
    # ArgumentError from their constructors — which, by the time it reaches a browser, is the 500
    # this exists to prevent.
    def tournament_id_refusal
      return if @tournament_id.match?(TOURNAMENT_ID_RE)

      "The Limitless tournament id must be a number — it is interpolated into the URL this fetches."
    end

    # The pool is resolved here, before the fetch, and memoised for the plan: the run refuses the
    # same set for the same reason, so refusing it while there is still a form on screen costs one
    # query and saves an Import row that could only ever fail.
    def pool_refusal
      return unless online?

      @standard_pool = Tournaments::LimitlessImportJob.standard_pool_for(@set)
      nil
    rescue Tournaments::LimitlessImportJob::PoolUnresolvable => e
      e.message
    end

    def source_rows
      return Tournaments::LimitlessEventResults.call(@tournament_id) if event?
      return Tournaments::LimitlessResults.call(@deck_id) unless online?

      Tournaments::OnlineResults.call(@slug, format: Tournaments::LimitlessImportJob::ONLINE_FORMAT,
        rotation: @rotation, set: @set)
    end

    # What the rows cannot say and the caller knows: an online leaderboard is anchored to the pool
    # its `set` names, and its arbitrary event names must never be read for a tier. The paper source
    # passes neither and keeps the plan's own defaults.
    #
    # An event run declares one thing more — that every row belongs to *one* real-world event, and
    # what the source's id for it is. Its pool comes off its own pages ("TEF-PBL" is
    # StandardPool#name byte for byte), so a code matching no pool arrives here as nil and the plan
    # blocks the event naming it, rather than being anchored by a date the source never claimed
    # anything about.
    def classification(rows)
      return { online: true, standard_pool: @standard_pool } if online?
      return {} unless event?

      { standard_pool: Tournaments::LimitlessImportJob.published_pool_for(rows),
        event_key: Tournaments::LimitlessImportJob.event_key_for(@tournament_id),
        max_rows: Tournaments::LimitlessImportJob::EVENT_MAX_ROWS }
    end

    def source_label
      return "Limitless tournament #{@tournament_id}" if event?
      return "Limitless deck #{@deck_id}" unless online?

      "the online #{@slug} leaderboard (#{@rotation} #{@set})"
    end

    # The event's own name is not available here — #create never fetches — so the id is what the
    # admin table prints. It is also what the receipt is read back under.
    def import_label
      return "Limitless tournament #{@tournament_id}" if event?

      "#{@archetype.name} — #{online? ? "online #{@slug} (#{@rotation} #{@set})" : "Limitless deck #{@deck_id}"}"
    end

    # One line per distinct deck reference, never one per row: 24 fixture rows carry 15 decks, and
    # 575 rows on the measured event carry 45. A reference the store already answers for costs
    # nothing at all, so the second event only asks about decks nobody has seen before.
    #
    # The lists come off Tournaments::EventDecklists, which fetches one bulk page per division and
    # answers every rank on it — which is what makes proposing for 45 decks one request rather
    # than 45.
    def mapping_lines(rows)
      grouped = rows.select { |row| row.archetype_key.present? }.group_by(&:archetype_key)
      # Indexed out of the collection the selects are rendered from, so a confirmed line costs no
      # query of its own.
      known = @archetypes.index_by(&:id)
      confirmed = LimitlessArchetypeMapping.by_reference(grouped.keys)
      decklists = Tournaments::EventDecklists.new(@tournament_id)

      grouped.map do |reference, group|
        label = group.filter_map { |row| row.archetype_label.presence }.first || reference
        mapping = confirmed[reference]
        if mapping
          MappingLine.new(reference: reference, label: label, confirmed: known[mapping.archetype_id])
        else
          propose(decklists, reference, label, group)
        end
      end
    end

    # One representative row per reference — the list is being read for what deck it is, and every
    # row carrying this reference is that deck.
    def propose(decklists, reference, label, group)
      row = group.find { |candidate| candidate.list_url.present? }
      if row.nil?
        return MappingLine.new(reference: reference, label: label,
          error: "Limitless published no list for this deck")
      end

      proposal = Tournaments::ArchetypeProposer.call(
        list_text: decklists.call(row.list_url), label: label, archetypes: @archetypes)
      MappingLine.new(reference: reference, label: label, proposal: proposal)
    rescue Tournaments::EventDecklists::ParseError, Tournaments::LimitlessDecklist::ParseError => e
      # A deck whose representative published nothing readable is ordinary — 4 of 8 Masters rows
      # here, 6 of 10 on Cape Town — and it must cost its own line rather than the other 44
      # proposals. The admin picks that one by hand.
      MappingLine.new(reference: reference, label: label, error: e.message)
    end

    # What the admin arbitrated, keyed on the deck reference Limitless published. Written before
    # the run is enqueued because the plan reads the store itself, which is also why nothing about
    # archetypes travels in the job's arguments.
    #
    # An `update!` rather than a create: a reference already confirmed is corrected in place, which
    # is what the two partial UNIQUE indexes guarantee against a second row.
    def persist_mappings
      selections = mapping_selections
      return if selections.empty?

      # Re-resolved rather than trusted: these came back through the browser. A selection naming an
      # archetype deleted between the two clicks is dropped, which leaves that deck's rows blocked
      # by name — exactly what leaving it blank does, and a better answer than throwing away the
      # other 44 confirmations or 500ing on the click.
      archetypes = Archetype.where(id: selections.map { |selection| selection[:archetype_id] }).index_by(&:id)

      selections.each do |selection|
        archetype = archetypes[selection[:archetype_id]]
        next if archetype.nil?

        LimitlessArchetypeMapping
          .find_or_initialize_by(limitless_deck_id: selection[:deck_id], limitless_variant: selection[:variant])
          .update!(archetype: archetype, label: selection[:label])
      end
    end

    # The selects and their labels, as the form sends them: `mappings[284/3][archetype_id]` and
    # `mappings[284/3][label]`. The label travels with the selection because
    # limitless_archetype_mappings.label is NOT NULL and this action never fetches — nothing else
    # on the POST could say what deck 284/3 is called.
    #
    # A key that is not a deck reference at all is dropped here: a form field name is user input.
    def mapping_selections
      raw = params[:mappings]
      return [] unless raw.respond_to?(:to_unsafe_h)

      raw.to_unsafe_h.filter_map do |reference, attributes|
        parsed = LimitlessArchetypeMapping.parse_reference(reference)
        # The key *and* the value, because both are a form field name away from being anything at
        # all. `respond_to?(:[])` was true of a String ("x"[:archetype_id] is a TypeError) and of an
        # Array (Array#to_i does not exist), so `mappings[284]=x` and
        # `mappings[284][archetype_id][]=1` were unrescued 500s on an admin screen.
        next if parsed.nil? || !attributes.is_a?(Hash)

        archetype_id = scalar(attributes[:archetype_id])&.presence&.to_i
        next if archetype_id.nil?

        { deck_id: parsed.first, variant: parsed.last, archetype_id: archetype_id,
          label: scalar(attributes[:label])&.presence || reference }
      end
    end

    # A submitted value the browser's own form could have produced, and nothing else: a nested Hash
    # or an Array here is a hand-made request, and reading it as a label or an id is how a 500
    # arrives on a screen whose every other refusal is a redirect.
    def scalar(value)
      value.to_s if value.is_a?(String) || value.is_a?(Numeric)
    end

    def job_options
      # String keys: an ActiveJob argument is serialized, and a Hash with Symbol keys comes back
      # from the queue with String ones anyway. Spelling them out here means the job reads the
      # same shape in a test that enqueues inline and in production.
      common = { "event_filters" => @event_filters, "limit_per_event" => @limit_per_event }
      # No expected_row_count for an event run, and the absence is a decision rather than an
      # omission. The count the admin looked at is *not* the count that run will write: confirming
      # the mappings is itself what unblocks those rows, so a count taken from a plan built before
      # that write drifts by construction and would refuse every first run. What the guard exists
      # for — a new event published between the two clicks — cannot happen to a run addressed by
      # one event id.
      return common.merge("source" => EVENT_SOURCE, "tournament_id" => @tournament_id) if event?

      common = common.merge(
        "archetype_id" => @archetype.id,
        # The row count the admin actually looked at. The job refetches rather than trusting a
        # plan carried through the browser, and refuses if the refetch no longer agrees — without
        # it, a new event published between the two clicks silently imports rows nobody approved.
        "expected_row_count" => params[:expected_row_count].to_i
      )
      # The paper source names no source at all, and the job reads its absence as paper: that is
      # also the shape of a run enqueued before this screen learned there were two of them.
      return common.merge("deck_id" => @deck_id) unless online?

      common.merge("source" => ONLINE_SOURCE, "slug" => @slug, "rotation" => @rotation, "set" => @set)
    end
  end
end
