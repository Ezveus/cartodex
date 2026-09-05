module Tournaments
  # One line of an event's public standings sheet. Wiki-governed: every write is open to any
  # signed-in member, so there is no owner scope on the *standing* — but the *participation* a row
  # is linked to is always looked up through current_user.tournament_entries, so a stranger's
  # entry is a RecordNotFound rather than a policy question.
  #
  # These routes leave the app-wide `authenticate :user` block by nesting under `tournaments`
  # alone. This controller therefore does NOT include PubliclyReachable: it keeps
  # authenticate_user! as its only gate and calls authorize in every action — the same deliberate
  # exception Tournaments::EntriesController and DeckResultsController are, with the same
  # consequence that nothing enforces the authorize call being present, which is what
  # test/controllers/public_access_test.rb covers per action.
  class StandingsController < ApplicationController
    before_action :set_tournament
    # claim and unclaim both need @standing, exactly as edit/update/destroy do — Rails 7.1+'s
    # raise_on_missing_callback_actions is why Task 6 could not name them here before the
    # actions themselves existed.
    before_action :set_standing, only: %i[edit update destroy claim unclaim]

    # Preflight ruling 3. See #refuse_with_redirect below for why this controller carries its own
    # handler rather than leaning on a shared one.
    rescue_from Pundit::NotAuthorizedError, with: :refuse_with_redirect

    def new
      @entry = scoped_entry(params[:tournament_entry_id])
      @standing = @tournament.standings.build(prefill_attributes(@entry))
      authorize @standing, :create?
    end

    def create
      @standing = @tournament.standings.build(standing_params)
      authorize @standing, :create?
      @entry = scoped_entry(params[:tournament_entry_id])
      @standing.created_by = current_user
      @standing.tournament_entry = @entry

      if @standing.save
        enqueue_list_import
        redirect_to sheet_path(@standing), notice: "Standing recorded."
      else
        @existing = existing_standing
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @standing
    end

    def update
      authorize @standing

      if @standing.update(standing_params)
        enqueue_list_import
        redirect_to sheet_path(@standing), notice: "Standing updated."
      else
        @existing = existing_standing
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @standing
      # Read before the row goes: the page it was on is where the rest of its neighbours still
      # are, and it is where the member was standing when they clicked. If it was the last row of
      # the last page, TournamentsController#show clamps the now-empty page back into range.
      page = TournamentStanding.page_of(@standing)
      @standing.destroy
      # Re-clamped after the row goes, not only when #show renders: deleting the only row of the
      # last page leaves a ?page= in the address bar that no longer exists, which the render
      # silently ignores and a reload or a shared link keeps repeating.
      redirect_to tournament_path(@tournament, page: page_param(surviving_page(page))),
        notice: "Standing deleted."
    end

    # The act of a member saying "the row naming this player is me". It writes the link and
    # nothing else: the public data on the row stays whatever whoever typed it wrote, and
    # correcting it is an ordinary wiki edit.
    #
    # A player with no account cannot do this, and that is not a gap: claiming *is* a member
    # linking their own participation, which is the whole reason the two tables are separate.
    def claim
      authorize @standing, :claim?
      @standing.tournament_entry = scoped_entry!(params[:tournament_entry_id])

      if @standing.save
        redirect_to sheet_path(@standing), notice: "Standing linked to your participation."
      else
        # full_messages, not errors[:tournament_entry]: a save re-runs *every* validation, not only
        # the one being changed, and a row can go invalid after it was written —
        # placement_within_division_field reads the event's field sizes, which the event's creator
        # may lower below a placement already recorded. Reading the one key made that refusal a
        # redirect with a blank alert, which tells the member nothing about why their click did
        # nothing. There is no form to re-render for a claim (it is a button, not a page), so the
        # same redirect-with-alert shape #refuse_with_redirect gives an authorization refusal is
        # what a validation refusal gets too: somewhere to go, and the reason why.
        # sheet_path, not the bare event: a refused claim leaves the row standing, and an alert
        # about a row the member cannot see is an alert about nothing.
        redirect_to sheet_path(@standing), alert: @standing.errors.full_messages.to_sentence
      end
    end

    def unclaim
      authorize @standing, :unclaim?
      # update_column, not update!, for the reason DecksController#share writes its flag that way:
      # severing a link the claimant put there has no business asking whether the *rest* of the row
      # is still valid, and a row really can go invalid after it was written — lower the event's
      # masters field below a placement already recorded and update! raises RecordInvalid, which
      # nothing here rescues, so "Unlink" answered with a 500. Nothing this write could break can
      # be broken by it: both validations that read tournament_entry return early on nil.
      @standing.update_column(:tournament_entry_id, nil)
      redirect_to sheet_path(@standing), notice: "Standing unlinked from your participation."
    end

    private

    def set_tournament
      # Unscoped: the event is public, and cataloguing its field is open to every member.
      @tournament = Tournament.with_standard_pool.find(params[:tournament_id])
    end

    # An event and its sheet are public — the event is *listed* at /tournaments — so a refusal
    # must say so and give the member somewhere to go, not answer with the deck rule's 404.
    # The same call TournamentsController#refuse_with_redirect makes, and this controller needs
    # its own: nothing outside PubliclyReachable rescues this exception, and the app's other
    # non-public controllers never reach a real Pundit refusal because their lookups are
    # user-scoped (every refusal there is already a RecordNotFound). Only #unclaim can refuse a
    # signed-in member here, and unrescued it would be a 500.
    #
    # params[:tournament_id] is always present: every route in this controller is nested.
    def refuse_with_redirect
      redirect_to tournament_path(params[:tournament_id]),
        alert: "Only the member whose participation is linked can unlink it."
    end

    def set_standing
      # Scoped by @tournament, not merely by id: a row belonging to another event must 404 rather
      # than render under this event's header — the reason Tournaments::EntriesController scopes
      # its entry by both.
      @standing = @tournament.standings.find(params[:id])
    end

    # A participation named by a request parameter, resolved through the reader's *own* entries at
    # *this* event, so a stranger's id is a RecordNotFound and never a policy question. nil when
    # no id was given, which is the ordinary "I am recording somebody else's row" case.
    def scoped_entry(id)
      return if id.blank?

      current_user.tournament_entries.find_by!(id: id, tournament_id: @tournament.id)
    end

    # #claim's entry is mandatory — the whole action is "link this row to that participation" —
    # so a missing id must be a RecordNotFound rather than a silent no-op that reports success.
    def scoped_entry!(id)
      current_user.tournament_entries.find_by!(id: id, tournament_id: @tournament.id)
    end

    # Values *copied* from the reader's own participation, never derived from it: editing the
    # private record afterwards must not silently republish. The row is wiki-editable, so
    # correcting it is an ordinary edit — there is no resync mechanism, by design.
    #
    # The W-L-T is deliberately not prefilled: a participation records a placement and CP, not a
    # match record, and the reader's DeckResults are not the event's official line.
    def prefill_attributes(entry)
      return {} if entry.nil?

      profile = entry.tournament_profile
      {
        player_name: profile&.player_name,
        # A division is fixed for the whole season, so it is asked of the *event's* date rather
        # than of today — and #division answers with a Symbol the enum column will not take.
        #
        # Dropped entirely on an online event, the way it is already dropped for a participation
        # with no TournamentProfile: a Play! Pokémon age division means nothing there, and copying
        # one here re-opens the defect Standings::Form#offered_divisions was written to close.
        # `division_options` would add the copied value back as the row's "own" one — correct for
        # the edit case it exists for — and `selected:` would prefer it over "open", so the form
        # would offer Open *and* Masters with Masters pre-selected.
        division: (profile&.division(on: @tournament.date)&.to_s unless @tournament.online?),
        placement: entry.placement,
        archetype_id: entry.deck.archetype_id
      }.compact
    end

    # The row the failed save collided with, so the form can link to it and offer to claim it
    # instead of merely refusing — what TournamentsController#create does for a duplicate event.
    # nil unless the failure really was the uniqueness rule.
    def existing_standing
      return if @standing.errors[:player_name].none?

      @tournament.standings.find_by(
        player_name_normalized: @standing.player_name_normalized, division: @standing.division
      )
    end

    # The standing is saved either way, so its row exists before its list does: a scrape that
    # fails must not lose the row somebody typed. Absent a decklist, nothing is enqueued.
    def enqueue_list_import
      decklist = params[:decklist].to_s
      return if decklist.strip.empty?

      import = current_user.imports.create!(
        kind: "standing_list", label: "#{@standing.player_name} — #{@tournament.name}",
        # Which event's page should list this while it runs. Without it every event page listed
        # every field-list import the reader had in flight, wherever it was started.
        tournament: @tournament
      )
      # Ids, not records: the job outlives the request, governance is wiki, so any member may
      # delete this standing (or the event, which cascades) while it is queued. GlobalID
      # deserialization of a deleted record raises ActiveJob::DeserializationError *before*
      # #perform runs, which no rescue inside the method can see — the import would then sit at
      # "pending" forever, with Admin::ImportsController#retry refusing this kind and no other way
      # to clear it.
      Tournaments::StandingListImportJob.perform_later(
        @standing.id, decklist, current_user.id, import.id
      )
    end

    # tournament_entry_id is deliberately absent. Permitting it would let any member attach their
    # own participation to a row naming somebody else, or detach yours: the link is written only
    # by #claim and #unclaim, from an id resolved through scoped_entry.
    # Every one of these actions used to redirect to the event, which was the same place as the row
    # until the sheet grew a pager. A member who adds the three-hundredth standing, or claims one
    # on page six, must not be answered with a page that does not contain the row they just acted
    # on — so the redirect names the page it actually falls on and anchors to the row itself.
    def sheet_path(standing)
      tournament_path(@tournament, **Tournaments::Standings::Row.sheet_position(standing))
    end

    def surviving_page(page)
      last = (@tournament.standings.count / TournamentStanding::SHEET_PER_PAGE.to_f).ceil
      page.clamp(1, [ last, 1 ].max)
    end

    # nil for page one, so the ordinary case keeps the bare, shareable URL it has always had.
    def page_param(page) = (page unless page == 1)

    def standing_params
      params.require(:tournament_standing).permit(
        :player_name, :division, :placement, :wins, :losses, :ties, :archetype_id
      )
    end
  end
end
