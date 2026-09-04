module Admin
  # "Import an archetype's field from Limitless TCG" — the one screen this feature has.
  #
  # No Pundit call anywhere below: Admin::BaseController#require_admin! is the whole gate for this
  # namespace, and an `authorize` here would be the only one in the panel.
  #
  # The screen is deliberately two requests. `preview` reads Limitless once and renders what a run
  # *would* write — which event each row lands in, the derived tier, format and division, what is
  # already there — because everything this writes goes into a public catalog that no member can
  # tell an import from a hand-typed row in. `create` is the click that follows.
  class StandingsImportsController < BaseController
    # The Limitless deck id is interpolated into a URL that is then fetched, so it is narrowed
    # here, before it can reach one. HttpFetcher refuses a non-HTTP URI as a backstop, but a
    # backstop is not the same as the caller saying what it will interpolate — and this is the
    # only place that can refuse while there is still a form to send the admin back to.
    DECK_ID_RE = /\A\d+\z/

    before_action :read_form_params, only: %i[new preview]

    def new; end

    # A GET. See the routes file for why it cannot be the POST it looks like.
    def preview
      return refuse("The Limitless deck id must be a number — it is interpolated into the URL this fetches.") unless
        @deck_id.match?(DECK_ID_RE)
      return refuse("Pick the archetype every imported row will carry.") if @archetype.nil?

      @plan = Tournaments::StandingsImportPlan.call(
        rows: Tournaments::LimitlessResults.call(@deck_id),
        event_filters: @event_filters,
        limit_per_event: @limit_per_event
      )
      render :new
    rescue Tournaments::LimitlessResults::ParseError, HttpFetcher::FetchError => e
      # Both are reachable from one wrong number in a text field — a deck id nobody has published,
      # a page whose layout moved, a rate limit. Re-rendering the form with the reason is the only
      # answer that leaves the admin somewhere to go; a 500 is not.
      refuse("Could not read Limitless deck #{@deck_id}: #{e.message}")
    end

    def create
      deck_id = params[:deck_id].to_s.strip
      archetype = Archetype.find_by(id: params[:archetype_id])
      # Re-validated rather than trusted: the confirm form carries these back through the browser,
      # which makes them ordinary user input again however carefully the preview checked them.
      refusal = refusal_for(deck_id, archetype)
      return redirect_to(new_admin_standings_import_path, alert: refusal) if refusal

      import = current_user.imports.create!(
        kind: "limitless_standings",
        label: "#{archetype.name} — Limitless deck #{deck_id}"
      )
      Tournaments::LimitlessImportJob.perform_later(import.id, current_user.id, job_options(deck_id, archetype))

      redirect_to admin_imports_path,
        notice: "Importing #{archetype.name} from Limitless deck #{deck_id}. Watch this table for the result."
    end

    # "Undo this run". `params[:id]` is an *Import* id: the run left its receipt there
    # (imports.created_standing_ids) and there is no standings-import record to address.
    def destroy
      import = Import.find(params[:id])
      unless import.kind == "limitless_standings"
        return redirect_to admin_imports_path,
          alert: "Only a Limitless standings import can be undone — this one is a #{import.kind} import."
      end

      result = Tournaments::StandingsImportUndo.call(import)
      redirect_to admin_imports_path, notice: undo_notice(result)
    end

    private

    def read_form_params
      @deck_id = params[:deck_id].to_s.strip
      @archetype_id = params[:archetype_id].presence&.to_i
      @archetype = Archetype.find_by(id: @archetype_id)
      @event_filters_text = params[:event_filters].to_s
      @event_filters = parse_filters(@event_filters_text)
      @limit_per_event_text = params[:limit_per_event].to_s.strip
      @limit_per_event = @limit_per_event_text.presence&.to_i
      @archetypes = Archetype.order(:name)
    end

    # One filter per line *or* comma-separated, because both are how a list of event names gets
    # typed: pasted off a schedule it arrives one per line, written by hand it arrives with commas.
    def parse_filters(text)
      text.split(/[\n,]/).map(&:strip).reject(&:empty?)
    end

    def refuse(message)
      flash.now[:alert] = message
      render :new
    end

    def refusal_for(deck_id, archetype)
      return "The Limitless deck id must be a number." unless deck_id.match?(DECK_ID_RE)
      return "That archetype no longer exists — pick one and preview again." if archetype.nil?

      nil
    end

    def job_options(deck_id, archetype)
      # String keys: an ActiveJob argument is serialized, and a Hash with Symbol keys comes back
      # from the queue with String ones anyway. Spelling them out here means the job reads the
      # same shape in a test that enqueues inline and in production.
      {
        "deck_id" => deck_id,
        "archetype_id" => archetype.id,
        "event_filters" => parse_filters(params[:event_filters].to_s),
        "limit_per_event" => params[:limit_per_event].presence&.to_i,
        # The row count the admin actually looked at. The job refetches rather than trusting a
        # plan carried through the browser, and refuses if the refetch no longer agrees — without
        # it, Limitless publishing an event between the two clicks silently imports rows nobody
        # approved.
        "expected_row_count" => params[:expected_row_count].to_i
      }
    end

    def undo_notice(result)
      "Undo complete: #{result.destroyed} standings deleted, " \
        "#{result.kept_claimed} left alone because a member has claimed them."
    end
  end
end
