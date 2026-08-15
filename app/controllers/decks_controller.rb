class DecksController < ApplicationController
  include Searchable

  def index
    # Ordered by name so the spotlight's "See all N decks" lands on a page whose first rows are
    # the ones it just showed — it orders by name too.
    @decks = filter_decks(current_user.decks.order(:name).includes(:deck_cards, :deck_results, archetype: [ :primary_pokemon, :secondary_pokemon ]))
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

  def show
    @deck = current_user.decks.includes(:archetype, :tournaments, deck_cards: :card, deck_results: []).find(params[:id])
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
    @editing = false

    if @deck.physical?
      @availability = Allocations::Availability.for_cards(
        user: current_user, cards: @deck.deck_cards.map(&:card), excluding_deck: @deck
      )
      @over_allocated_card_ids = Allocations::OverAllocations.call(user: current_user).map { |o| o[:card_id] }.to_set
    else
      @availability = {}
      @over_allocated_card_ids = Set.new
    end
  end

  def stats
    @deck = current_user.decks.includes(:archetype).find(params[:id])
    @results = @deck.deck_results.includes(archetype: [ :parent, :primary_pokemon, :secondary_pokemon ])
  end

  # Aggregated matchup breakdown grouped by the player's own deck archetype:
  # for each archetype, all results across the user's decks of that archetype,
  # split by the opposing archetype.
  def matchups
    decks = current_user.decks
      .where.not(archetype_id: nil)
      .includes(:archetype, deck_results: { archetype: [ :parent, :primary_pokemon, :secondary_pokemon ] })

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
    ids = Array(params[:ids]).map(&:to_i).uniq
    decks = current_user.decks.where(id: ids).includes(deck_cards: :card)
    decks = decks.sort_by { |deck| ids.index(deck.id) }

    if decks.size < 2 || decks.size > 4
      redirect_to decks_path, alert: "Select 2 to 4 decks to compare." and return
    end

    @comparison = Decks::Comparator.call(decks)
  end

  def export
    deck = current_user.decks.includes(deck_cards: { card: [ :attacks, :abilities ] }).find(params[:id])

    case params[:style]
    when "tournament_pdf"
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
  end

  def create
    @deck = current_user.decks.build(deck_params)

    if @deck.save
      redirect_to @deck, notice: "Deck created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @deck = current_user.decks.includes(:archetype, :tournaments, deck_cards: :card, deck_results: []).find(params[:id])
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
    @editing = true
    render :show
  end

  def update
    @deck = current_user.decks.find(params[:id])

    if @deck.update(deck_params)
      @editing = false
      render :update, layout: false
    else
      @editing = true
      render :update, layout: false, status: :unprocessable_entity
    end
  end

  def destroy
    deck = current_user.decks.find(params[:id])
    deck.destroy
    redirect_to decks_path, notice: "Deck deleted."
  end

  def duplicate
    source = current_user.decks.find(params[:id])
    new_deck = Decks::Duplicator.call(source)
    redirect_to new_deck, notice: "Deck duplicated."
  end

  private

  # True when Turbo is refreshing just the deck grid (the filter form targets it) rather than
  # loading the whole page.
  def results_frame_request?
    request.headers["Turbo-Frame"] == Decks::IndexView::FRAME_ID
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

  # Primary Pokémon of the archetypes used by the current user's decks, for the filter bar.
  def primary_filter_options
    pokemon_filter_options(:primary_pokemon_id)
  end

  # Secondary Pokémon of the archetypes used by the current user's decks, for the filter bar.
  def secondary_filter_options
    pokemon_filter_options(:secondary_pokemon_id)
  end

  def pokemon_filter_options(column)
    archetype_ids = current_user.decks.where.not(archetype_id: nil).select(:archetype_id)
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
      scope = scope.where(archetypes: { primary_pokemon_id: filters[:primary] }) if filters[:primary]
      scope = scope.where(archetypes: { secondary_pokemon_id: filters[:secondary] }) if filters[:secondary]
    end

    scope
  end

  def deck_params
    params.require(:deck).permit(:name, :description, :physical, :tcg_live, :format, :other_format_name, :archetype_id)
  end
end
