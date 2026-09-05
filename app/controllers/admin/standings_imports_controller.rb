module Admin
  # "Import an archetype's field from Limitless" — the one screen this feature has, now reading
  # either of two sources: the paper events at limitlesstcg.com/decks/<id>/results, and the online
  # best finishes at play.limitlesstcg.com/decks/<slug>.
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

    ONLINE_SOURCE = "online".freeze
    DEFAULT_SOURCE = "paper".freeze

    before_action :read_form_params
    # Only where a form is rendered: `create` answers with a redirect either way, and the select
    # would be a query spent on a page nobody sees.
    before_action :load_archetypes, only: %i[new preview]

    def new; end

    # A GET. See the routes file for why it cannot be the POST it looks like.
    def preview
      message = refusal("Pick the archetype every imported row will carry.")
      return refuse(message) if message

      @plan = Tournaments::StandingsImportPlan.call(
        rows: source_rows, event_filters: @event_filters, limit_per_event: @limit_per_event,
        **classification
      )
      render :new
    rescue Tournaments::LimitlessResults::ParseError, Tournaments::OnlineResults::ParseError,
      HttpFetcher::FetchError => e
      # All three are reachable from one wrong value in a text field — a deck id or a slug nobody
      # has published, a rotation and set naming an empty leaderboard, a page whose layout moved, a
      # rate limit. Re-rendering the form with the reason is the only answer that leaves the admin
      # somewhere to go; a 500 is not. OnlineResults::ParseError is named beside its paper twin
      # because it is a *different constant* — a source switch that rescued only the old one would
      # answer a mistyped slug with that 500.
      refuse("Could not read #{source_label}: #{e.message}")
    end

    def create
      # Re-validated rather than trusted: the confirm form carries these back through the browser,
      # which makes them ordinary user input again however carefully the preview checked them.
      message = refusal("That archetype no longer exists — pick one and preview again.")
      return redirect_to(new_admin_standings_import_path, alert: message) if message

      import = current_user.imports.create!(kind: "limitless_standings", label: import_label)
      Tournaments::LimitlessImportJob.perform_later(import.id, current_user.id, job_options)

      redirect_to admin_imports_path,
        notice: "Importing #{@archetype.name} from #{source_label}. Watch this table for the result."
    end

    # "Undo this run". `params[:id]` is an *Import* id: the run left its receipt there
    # (imports.created_standing_ids) and there is no standings-import record to address.
    private

    def read_form_params
      @source = params[:source].to_s == ONLINE_SOURCE ? ONLINE_SOURCE : DEFAULT_SOURCE
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
      source_refusal || (archetype_message if @archetype.nil?) || pool_refusal
    end

    def source_refusal
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
      return Tournaments::LimitlessResults.call(@deck_id) unless online?

      Tournaments::OnlineResults.call(@slug, format: Tournaments::LimitlessImportJob::ONLINE_FORMAT,
        rotation: @rotation, set: @set)
    end

    # What the rows cannot say and the caller knows: an online leaderboard is anchored to the pool
    # its `set` names, and its arbitrary event names must never be read for a tier. The paper source
    # passes neither and keeps the plan's own defaults.
    def classification
      return {} unless online?

      { online: true, standard_pool: @standard_pool }
    end

    def source_label
      return "Limitless deck #{@deck_id}" unless online?

      "the online #{@slug} leaderboard (#{@rotation} #{@set})"
    end

    def import_label
      "#{@archetype.name} — #{online? ? "online #{@slug} (#{@rotation} #{@set})" : "Limitless deck #{@deck_id}"}"
    end

    def job_options
      # String keys: an ActiveJob argument is serialized, and a Hash with Symbol keys comes back
      # from the queue with String ones anyway. Spelling them out here means the job reads the
      # same shape in a test that enqueues inline and in production.
      common = {
        "archetype_id" => @archetype.id,
        "event_filters" => @event_filters,
        "limit_per_event" => @limit_per_event,
        # The row count the admin actually looked at. The job refetches rather than trusting a
        # plan carried through the browser, and refuses if the refetch no longer agrees — without
        # it, a new event published between the two clicks silently imports rows nobody approved.
        "expected_row_count" => params[:expected_row_count].to_i
      }
      # The paper source names no source at all, and the job reads its absence as paper: that is
      # also the shape of a run enqueued before this screen learned there were two of them.
      return common.merge("deck_id" => @deck_id) unless online?

      common.merge("source" => ONLINE_SOURCE, "slug" => @slug, "rotation" => @rotation, "set" => @set)
    end
  end
end
