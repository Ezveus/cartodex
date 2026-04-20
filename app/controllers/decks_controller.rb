class DecksController < ApplicationController
  def index
    @decks = current_user.decks.includes(:deck_cards)
    @pending_deck_imports = current_user.imports.deck_imports.pending
  end

  def show
    @deck = current_user.decks.includes(deck_cards: :card, deck_results: []).find(params[:id])
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
    @editing = false
  end

  def stats
    @deck = current_user.decks.find(params[:id])
    @results = @deck.deck_results.includes(archetype: [ :parent, :primary_pokemon, :secondary_pokemon ])
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
    @deck = current_user.decks.includes(deck_cards: :card, deck_results: []).find(params[:id])
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

  def deck_params
    params.require(:deck).permit(:name, :description)
  end
end
