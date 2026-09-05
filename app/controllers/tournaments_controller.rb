# The catalog and one event's page are public reads; cataloguing and correcting an event are
# member writes. Both halves live here, the shape DecksController already has.
class TournamentsController < ApplicationController
  include Searchable
  include PubliclyReachable

  CATALOG_PER_PAGE = 24

  # 60/min, the number DecksController#shared carries, because the catalog is the same shape
  # and the same cost: a field debounced at 300ms driving a paginated listing behind a Turbo
  # Frame, so a keystroke pays the pager's COUNT and one page of rows. The cost half of that
  # only became true with the index on tournaments.date (20260904083908): #index orders by it,
  # and the (name_normalized, date) UNIQUE key leads with the wrong column to serve that sort.
  # Unlike decks#shared there is no `return if frame_request?` here, and none is needed —
  # nothing renders or queries outside the frame, so a frame request costs what a plain one
  # does (measured: 4 queries either way). #show gets none — one page load per click, with no
  # live control behind it, exactly as decks#show has none.
  CATALOG_RATE_LIMIT_TO = 60
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: CATALOG_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "tournaments-index", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :index

  before_action :set_tournament, only: %i[show edit update destroy]

  publicly_reachable :index, :show

  # An event's existence is public — it is listed at /tournaments — so "not yours" answers with
  # somewhere to go rather than with the deck rule's 404. PubliclyReachable's own handler routes
  # RecordNotFound and NotAuthorizedError onto one static 404; declaring this here, after the
  # include, wins for NotAuthorizedError alone, because rescue_from is consulted in reverse
  # order of declaration.
  rescue_from Pundit::NotAuthorizedError, with: :refuse_with_redirect

  def index
    authorize Tournament, :index?
    @query = search_query

    scope = Tournament.catalogued.order(date: :desc)
    scope = scope.name_matching(@query) if @query.present?

    @pages = (scope.count / CATALOG_PER_PAGE.to_f).ceil
    # Clamped for the reason the sheet is, one method below: `?page=99` otherwise renders "No
    # tournaments catalogued yet." over a catalog that is not empty, on a public URL.
    @page = requested_page.clamp(1, [ @pages, 1 ].max)
    # to_a, not the relation: the view asks `any?` before iterating, which on an unloaded
    # relation is a SELECT 1 … LIMIT 1 beside the query it is about to run anyway.
    @tournaments = scope.offset((@page - 1) * CATALOG_PER_PAGE).limit(CATALOG_PER_PAGE)
                        .with_standard_pool.to_a
    @attended_ids = attended_ids(@tournaments)
  end

  def show
    authorize @tournament
    @my_entries = my_entries
    @can_record_another = unrecorded_profile?
    load_standings_page
    @pending_standing_imports = pending_standing_imports
    @claimable_entries = claimable_entries
  end

  def mine
    authorize Tournament, :mine?
    # No with_standard_pool here: this list has no Format column, and preloading two card sets
    # per row for something nothing prints is the mistake that scope exists to fix.
    @entries = current_user.tournament_entries
      .joins(:tournament).includes(:deck, :tournament_profile, :tournament)
      .order("tournaments.date DESC").to_a
  end

  def new
    @tournament = Tournament.new(date: Date.current)
    authorize @tournament, :create?
  end

  def create
    @tournament = Tournament.new(tournament_params.merge(created_by: current_user))
    authorize @tournament, :create?

    if @tournament.save
      redirect_to new_tournament_entry_path(@tournament),
        notice: "Tournament added to the catalog. Now record your participation."
    else
      @existing = existing_tournament
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @tournament
  end

  def update
    authorize @tournament

    if @tournament.update(tournament_params)
      redirect_to @tournament, notice: "Tournament updated."
    else
      @existing = existing_tournament
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @tournament

    if @tournament.destroy
      redirect_to tournaments_path, notice: "Tournament deleted."
    else
      # restrict_with_error's own message names the association, not what a reader needs to
      # know, which is whose data is in the way and how much of it.
      count = @tournament.entries.count
      redirect_to @tournament,
        alert: "This tournament still has #{count} #{"participation".pluralize(count)} recorded against it."
    end
  end

  private

  def set_tournament
    @tournament = Tournament.with_standard_pool.find(params[:id])
  end

  # The event the failed save collided with, so the form can link to it instead of merely
  # refusing. nil unless the failure really was the uniqueness rule.
  # `catalogued`, because the validation that produced this error is: name_and_date_are_unique
  # returns early for an online record and searches Tournament.catalogued, matching the now-partial
  # UNIQUE index. Unscoped, the two disagree — an online event sharing a name and a date is
  # returned although it is not what refused the save, and since #index no longer lists it the
  # member follows a link to an event that is nowhere in the catalog they were just told it
  # collides with. With no catalogued clash at all it would invent a link for an error nothing
  # raised.
  def existing_tournament
    return if @tournament.errors[:name].none?

    Tournament.catalogued.find_by(name_normalized: @tournament.name_normalized, date: @tournament.date)
  end

  # Plural, because entry uniqueness is per Play! Pokémon profile rather than per user: a parent
  # tracking their own and their child's profiles legitimately has two participations in one
  # event, and a singular find_by picks one of them arbitrarily and hides the other from the
  # only page that links to it. tournament_profile is preloaded because the page names it —
  # that is what tells two of the reader's own entries apart.
  def my_entries
    return [] if current_user.nil?

    current_user.tournament_entries.where(tournament: @tournament)
      .includes(:tournament_profile, :standing).order(:id).to_a
  end

  # Whether the reader still has a player this event holds no participation for. Deliberately
  # narrower than TournamentEntry#one_entry_per_player and deliberately not a restatement of it:
  # it answers "another entry is obviously possible", so a reader it says no to loses a button
  # they might have been able to use, never gets a form that then refuses them.
  def unrecorded_profile?
    return false if current_user.nil?

    current_user.tournament_profiles
      .where.not(id: @my_entries.filter_map(&:tournament_profile_id)).exists?
  end

  # A hand-typed sheet is a handful of rows; an imported one is a Worlds field. This page is
  # public, carries no rate limit (one page load per click, which is why it never needed one) and
  # preloads three associations for every row it renders, so rendering the whole sheet was only
  # ever fine while nothing could fill it.
  #
  # No Turbo Frame, unlike the three listings that have one: those wrap a debounced filter field,
  # where a keystroke would otherwise pay for the whole surrounding page. Nothing here fires on
  # its own, and a frame would capture every link inside the rows — the deck link, Edit, Delete,
  # "This is me" — each of which would then need data-turbo-frame="_top" to keep working.
  def load_standings_page
    scope = @tournament.standings
    @sheet_pages = (scope.count / TournamentStanding::SHEET_PER_PAGE.to_f).ceil
    # Clamped rather than allowed to run off the end: an out-of-range page renders an empty table
    # under "No standings recorded for this event yet.", which is false — and this URL is public,
    # so something will try it.
    @sheet_page = requested_page.clamp(1, [ @sheet_pages, 1 ].max)
    # Exactly the three legs the render touches, each pinned by its own leg of the flat-cost test:
    # Row#list_link reads :deck, the "You" marker reads :tournament_entry's user_id, and
    # Ui::ArchetypeBadge reads only the archetype's name and primary_energy_type (which reads
    # primary_card) — never secondary_card or parent, so those two are not preloaded here.
    @standings = scope.as_a_sheet
      .offset((@sheet_page - 1) * TournamentStanding::SHEET_PER_PAGE)
      .limit(TournamentStanding::SHEET_PER_PAGE)
      .includes(:deck, :tournament_entry, archetype: :primary_card).to_a
  end

  # to_s first: `?page[]=1` hands over an Array and `?page[a]=b` ActionController::Parameters,
  # neither of which answers to_i. Both actions that read it are reachable without a session, so
  # that NoMethodError would be an unhandled 500 for any bot that tries the shape.
  def requested_page
    [ params[:page].to_s.to_i, 1 ].max
  end

  # Field-list imports the reader has in flight *at this event*. Empty for a visitor, and never
  # queried for one. Scoped by tournament, not merely by kind: an import started at another event
  # would otherwise be listed under this event's "Importing…" heading — and since the item's DOM
  # id is importing-<import id>, the completion broadcast for that other event would then remove a
  # row from a page it has nothing to do with.
  def pending_standing_imports
    return [] if current_user.nil?

    current_user.imports.pending.where(kind: "standing_list", tournament: @tournament).to_a
  end

  # The reader's own participations at this event that no standing names yet — one claim button
  # each. Plural for the reason my_entries is: entry uniqueness is per profile.
  def claimable_entries
    return [] if current_user.nil?

    @my_entries.reject(&:standing)
  end

  # One grouped query for the whole page, and none at all for a visitor.
  def attended_ids(tournaments)
    return Set.new if current_user.nil? || tournaments.empty?

    current_user.tournament_entries.where(tournament_id: tournaments.map(&:id))
      .pluck(:tournament_id).to_set
  end

  # rescue_from covers every action, and four of them — index, mine, new, create — carry no :id,
  # so a redirect helper that assumed one would turn a refusal into an UrlGenerationError 500.
  # Reachable from a collection action in principle only: index/mine/create authorize against
  # index?/create?/mine?, none of which can currently fail for a signed-in user, and
  # `publicly_reachable :index, :show` leaves authenticate_user! on new/create/mine, so a visitor
  # is bounced to sign-in before any of this runs. `.present?` rather than a bare truth test:
  # `?id=` on a collection action hands over "", which is truthy and which tournament_path
  # refuses. The id-less message therefore says nothing about sessions — nobody without one gets
  # here — and the id-ful one names both verbs this handler serves, edit and destroy alike.
  def refuse_with_redirect
    if params[:id].present?
      redirect_to tournament_path(params[:id]),
        alert: "Only the member who catalogued this tournament can change or delete it."
    else
      redirect_to tournaments_path, alert: "You don't have access to that."
    end
  end

  def tournament_params
    params.require(:tournament).permit(
      :name, :date, :format, :other_format_name, :standard_pool_id, :tier,
      :junior_participant_count, :senior_participant_count, :masters_participant_count,
      # open_participant_count is written by the online import, and it *caps* a placement through
      # TournamentStanding#placement_within_division_field — so a wrong value makes every standing
      # above it unsavable through the wiki edit form, and without this permit (and the matching
      # field on Tournaments::Form) there would be nowhere in the app to correct it.
      :open_participant_count
    )
  end
end
