class DecksController < ApplicationController
  include Searchable
  include PubliclyReachable

  publicly_reachable :show, :export, :shared

  SHARED_PER_PAGE = 24

  # Both numbers are derived, and both are for the two actions that lost the session gate.
  # #show is not among them: it is one page load per click, with no live control behind it.
  #
  # 60/min for the index because it is the same shape as CardsController#index — a field
  # debounced at 300ms driving a paginated listing — and now the same cost, too: the filter
  # form targets a Turbo Frame, so a keystroke pays the COUNT the pager needs and the page of
  # rows, not the archetype options query or the surrounding page. One request a second
  # sustained is well past what a debounced field emits; the amplifier was removed before the
  # rationing, as it was for /cards.
  #
  # 30/min for the export because nothing fires it automatically: it is a click on a dropdown
  # item, and the image export goes to the card proxy rather than here. Each request does
  # preload deck_cards → card → attacks/abilities for a whole deck, which is what makes 30
  # the right order of magnitude rather than 300 — and only an anonymous reader of a shared
  # deck spends it, since the owner is signed in and exempt.
  SHARED_RATE_LIMIT_TO = 60
  EXPORT_RATE_LIMIT_TO = 30
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: SHARED_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "decks-shared", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :shared

  rate_limit to: EXPORT_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "decks-export", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :export

  def index
    authorize Deck, :index?
    # Ordered by name so the spotlight's "See all N decks" lands on a page whose first rows are
    # the ones it just showed — it orders by name too.
    @decks = filter_decks(current_user.decks.order(:name).with_standard_pool.includes(
      :deck_cards, :deck_results, archetype: [ :primary_card, :secondary_card ]
    ))
    @filters = filter_params

    # Needed even for a frame request: the deck cards inside the frame flag their own
    # over-allocation from this set.
    over_allocations = Allocations::OverAllocations.call(user: current_user)
    @over_allocation_count = over_allocations.size
    @over_allocated_deck_ids = over_allocations.flat_map { |o| o[:decks].map { |d| d[:id] } }.to_set

    # A live-filter keystroke asks for the results frame alone, and Turbo throws the rest of the
    # response away. Everything below renders outside that frame, so don't pay for it on what is
    # now the app's most frequent request.
    return if results_frame_request?

    @pending_deck_imports = current_user.imports.deck_imports.pending
    @primary_options = primary_filter_options
    @secondary_options = secondary_filter_options
  end

  def shared
    authorize Deck, :shared_index?

    scope = Deck.shared.order(created_at: :desc)
    scope = scope.merge(Deck.search(search_query)) if search_query.present?
    scope = scope.where(format: params[:format]) if Deck.formats.key?(params[:format])
    scope = scope.joins(:archetype).where(archetypes: { primary_card_id: params[:primary] }) if params[:primary].present?

    # to_s first: `?page[a]=b` hands over ActionController::Parameters and `?page[]=1` an
    # Array, neither of which answers to_i. PubliclyReachable rescues RecordNotFound and
    # NotAuthorizedError and nothing else, so on this now-anonymous action that NoMethodError
    # would be an unhandled 500 for any bot that tries the shape.
    @page = [ params[:page].to_s.to_i, 1 ].max
    @pages = (scope.count / SHARED_PER_PAGE.to_f).ceil
    # Same preloads as the dashboard showcase; see Deck.with_standard_pool for why the badge
    # needs the pool's bounds too.
    # to_a, not the relation: the view asks `any?` before iterating, and on an unloaded
    # relation that is a SELECT 1 … LIMIT 1 beside the page query it is about to run anyway.
    @decks = scope.offset((@page - 1) * SHARED_PER_PAGE).limit(SHARED_PER_PAGE)
                  .with_standard_pool
                  .includes(:deck_cards, archetype: [ :primary_card, :secondary_card ]).to_a

    @filters = { q: search_query.presence, format: params[:format].presence, primary: params[:primary].presence }

    # A live-filter keystroke asks for the results frame alone; the filter bar lives outside
    # it and Turbo throws the rest of the response away. Same short-circuit as #index, and the
    # reason this endpoint could be rationed without rationing an amplifier.
    return if results_frame_request?(Decks::SharedIndexView::FRAME_ID)

    @archetype_options = shared_archetype_options
  end

  def show
    # The only unscoped deck lookup in the app that this feature creates. `authorize` is the
    # next line for that reason, and nothing else loads until it has run.
    @deck = Deck.find_by!(key: params[:id])
    authorize @deck

    if @deck.user_id == current_user&.id
      owner_show
    else
      public_show
    end
  end

  def stats
    @deck = current_user.decks.includes(:archetype).find_by!(key: params[:id])
    authorize @deck
    @results = @deck.deck_results.includes(archetype: [ :parent, :primary_card, :secondary_card ])
  end

  # Aggregated matchup breakdown grouped by the player's own deck archetype:
  # for each archetype, all results across the user's decks of that archetype,
  # split by the opposing archetype.
  def matchups
    authorize Deck, :index?
    decks = current_user.decks
      .where.not(archetype_id: nil)
      .includes(:archetype, deck_results: { archetype: [ :parent, :primary_card, :secondary_card ] })

    @matchup_groups = decks.group_by(&:archetype).map { |archetype, group|
      results = group.flat_map(&:deck_results)
      sample = group.first
      {
        archetype: archetype,
        deck_count: group.size,
        counts: sample.result_counts(results),
        breakdown: sample.archetype_breakdown(results)
      }
    }.sort_by { |g| -g[:counts].values.sum }
  end

  def compare
    authorize Deck, :index?
    keys = Array(params[:ids]).map(&:to_s).uniq
    decks = current_user.decks.where(key: keys).includes(deck_cards: :card)
    decks = decks.sort_by { |deck| keys.index(deck.key) }

    if decks.size < 2 || decks.size > 4
      redirect_to decks_path, alert: "Select 2 to 4 decks to compare." and return
    end

    @comparison = Decks::Comparator.call(decks)
  end

  def export
    @deck = Deck.find_by!(key: params[:id])
    authorize @deck, :export?

    deck = Deck.includes(deck_cards: { card: [ :attacks, :abilities ] }).find(@deck.id)

    case params[:style]
    when "tournament_pdf"
      # Reads one of the owner's profiles, so it is a stricter question than :export?.
      authorize @deck, :tournament_pdf?
      profile = current_user.tournament_profiles.find(params[:profile_id])
      pdf = Decks::TournamentPdfExporter.call(deck, profile)
      send_data pdf,
        type: "application/pdf",
        disposition: "attachment",
        filename: "#{deck.name.parameterize}-decklist.pdf"
    when "cardmarket"
      render json: { text: Decks::CardmarketExporter.call(deck) }
    else
      render json: { text: Decks::Exporter.call(deck) }
    end
  end

  def new
    @deck = Deck.new
    authorize @deck
  end

  def create
    @deck = current_user.decks.build(deck_params)
    authorize @deck

    if @deck.save
      redirect_to @deck, notice: "Deck created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @deck = current_user.decks.includes(:archetype, :tournaments, deck_cards: :card, deck_results: []).find_by!(key: params[:id])
    authorize @deck
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
    @editing = true
    render :show
  end

  def update
    # The re-rendered header carries the proxy badge, which reads the deck's cards.
    @deck = current_user.decks.includes(:deck_cards).find_by!(key: params[:id])
    authorize @deck

    if @deck.update(deck_params)
      @editing = false
      render :update, layout: false
    else
      @editing = true
      render :update, layout: false, status: :unprocessable_entity
    end
  end

  def destroy
    deck = current_user.decks.find_by!(key: params[:id])
    authorize deck
    deck.destroy
    redirect_to decks_path, notice: "Deck deleted."
  end

  def duplicate
    source = current_user.decks.find_by!(key: params[:id])
    authorize source
    new_deck = Decks::Duplicator.call(source)
    redirect_to new_deck, notice: "Deck duplicated."
  end

  def share
    @deck = current_user.decks.find_by!(key: params[:id])
    authorize @deck, :share?

    # An unchecked bare checkbox posts no `shared` param at all — nil against a NOT NULL
    # column raises. The form's hidden "0" field is the fix; `|| false` here is the belt.
    #
    # update_column, not update!: `validates :standard_pool, presence:, if: :standard?` would
    # be rejoined here, so a Standard deck whose anchor is still NULL — a row from before that
    # column, or any environment that skipped standard_pools:backfill_anchors — could be
    # neither shared nor unshared. The toggle has no business asking whether the rest of the
    # record is currently valid, and nothing caches on the deck's updated_at.
    @deck.update_column(:shared, ActiveModel::Type::Boolean.new.cast(params[:shared]) || false)

    # share has only a .turbo_stream.erb behind it. Unbranched, an `Accept: text/html`
    # request raises MissingTemplate *after* the write has committed — the flag flips and the
    # response is a 500. The deck page is where a non-Turbo client wanted to end up anyway.
    respond_to do |format|
      format.turbo_stream { render :share, layout: false }
      format.html { redirect_to @deck }
    end
  end

  private

  # PubliclyReachable's renderer, with the one branch the other three including controllers do
  # not need. A deck can be private, so "unknown key" and "not yours" have to stay one answer
  # — and for a request carrying no session, the answer that satisfies that *and* leads
  # somewhere is sign-in. Both outcomes redirect identically, so an anonymous scan of random
  # keys learns exactly what it learned from two identical 404s: nothing. What it buys is the
  # owner whose session expired, following their own bookmark, no longer landing on a static
  # page with no navbar, no sign-in link and no return-to.
  #
  # A signed-in request keeps the 404. Sign-in has nothing to offer someone already signed in,
  # and the two outcomes stay indistinguishable there too.
  #
  # CardsController deliberately does not do this: nothing in the catalog is private, so a
  # missing card is a missing card.
  def not_found
    return authenticate_user! unless user_signed_in?

    super
  end

  # Each branch reloads with the preloads it needs. `includes` chains onto `find_by!` perfectly
  # well — that is not the reason for the second query. The reason is that authorize runs first
  # and only then does the request know which set of preloads it wants: loading the owner's up
  # front would make a visitor's request pull deck_results and tournaments, exactly what the
  # public view exists to avoid, and loading anything before authorize does work for a deck the
  # caller may not see. One extra primary-key SELECT is the price of that ordering, in `export`
  # (which has no branch) as much as here.
  def owner_show
    @deck = current_user.decks.includes(:archetype, :tournaments, deck_cards: :card, deck_results: []).find(@deck.id)
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
    @editing = false
    # Which rows get a printing picker at all. Not restricted to physical decks: a swap changes
    # what every export prints, which is reason enough on a TCG Live deck.
    @swappable_card_ids = Cards::Printings.swappable_card_ids(@deck.deck_cards.map(&:card))

    if @deck.physical?
      @availability = Allocations::Availability.for_cards(
        user: current_user, cards: @deck.deck_cards.map(&:card), excluding_deck: @deck
      )
      @over_allocated_card_ids = Allocations::OverAllocations.call(user: current_user).map { |o| o[:card_id] }.to_set
    else
      @availability = {}
      @over_allocated_card_ids = Set.new
    end

    render :show
  end

  def public_show
    @deck = Deck.includes(deck_cards: :card).find(@deck.id)
    # Devise only remembers a location when authenticate_user! bounces a request, so without
    # this a visitor who clicks Sign in here lands on the dashboard and has to find the deck
    # again.
    store_location_for(:user, request.fullpath) if remember_return_to?
    render :public_show
  end

  # Only for a visitor who actually asked for this page. A signed-in member reading somebody
  # else's shared deck has a return-to of their own worth keeping, and Turbo 8 prefetches on
  # hover by default — unguarded, merely passing the cursor over a link would set the place
  # sign-in sends you to a deck you never opened (and a 404 if it is unshared by then).
  def remember_return_to?
    return false if user_signed_in?

    request.headers["X-Sec-Purpose"] != "prefetch" &&
      !request.headers["Sec-Purpose"].to_s.include?("prefetch")
  end

  # True when Turbo is refreshing just the deck grid (the filter form targets it) rather than
  # loading the whole page. The owner's index and the shared one have a frame each.
  def results_frame_request?(frame_id = Decks::IndexView::FRAME_ID)
    request.headers["Turbo-Frame"] == frame_id
  end

  def filter_params
    {
      q:         search_query.presence,
      format:    params[:format].presence,
      support:   params[:support].presence,
      proxies:   params[:proxies].presence,
      primary:   params[:primary].presence,
      secondary: params[:secondary].presence
    }
  end

  # Primary card of the archetypes used by the current user's decks, for the filter bar.
  def primary_filter_options
    archetype_card_options(current_user.decks, :primary_card_id)
  end

  # Secondary card of the archetypes used by the current user's decks, for the filter bar.
  def secondary_filter_options
    archetype_card_options(current_user.decks, :secondary_card_id)
  end

  # Derived from the shared decks, deliberately not from the current user's: that scope would
  # offer a visitor a filter built from nobody's decks, and a member one that hides most of the
  # page. The three stay named because they are three different questions; only the query they
  # all ask is written once.
  def shared_archetype_options
    archetype_card_options(Deck.shared, :primary_card_id)
  end

  # "The cards these decks' archetypes point at", as [name, id] pairs for a filter <select>.
  def archetype_card_options(decks, column)
    archetype_ids = decks.where.not(archetype_id: nil).select(:archetype_id)
    card_ids = Archetype.where(id: archetype_ids).select(column)
    Card.where(id: card_ids).order(:name).pluck(:name, :id)
  end

  def filter_decks(scope)
    filters = filter_params

    # Same scope as the dashboard spotlight, so its "See all N decks" link lands on a page
    # showing exactly N decks.
    scope = scope.merge(Deck.search(filters[:q])) if filters[:q]

    scope = scope.where(format: filters[:format]) if Deck.formats.key?(filters[:format])

    case filters[:support]
    when "physical" then scope = scope.where(physical: true)
    when "tcg_live" then scope = scope.where(tcg_live: true)
    end

    case filters[:proxies]
    when "with"    then scope = scope.with_proxies
    when "without" then scope = scope.without_proxies
    end

    if filters[:primary] || filters[:secondary]
      scope = scope.joins(:archetype)
      scope = scope.where(archetypes: { primary_card_id: filters[:primary] }) if filters[:primary]
      scope = scope.where(archetypes: { secondary_card_id: filters[:secondary] }) if filters[:secondary]
    end

    scope
  end

  def deck_params
    params.require(:deck).permit(
      :name, :description, :physical, :tcg_live, :format, :other_format_name, :archetype_id, :standard_pool_id
    )
  end
end
