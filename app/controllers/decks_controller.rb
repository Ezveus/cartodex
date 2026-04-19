class DecksController < ApplicationController
  def index
    @decks = current_user.decks.includes(:deck_cards)
    @pending_deck_imports = current_user.imports.deck_imports.pending
  end

  def show
    @deck = current_user.decks.includes(deck_cards: :card, deck_results: []).find(params[:id])
  end

  def stats
    @deck = current_user.decks.find(params[:id])
    @results = @deck.deck_results.includes(archetype: [ :parent, :primary_pokemon, :secondary_pokemon ])
  end

  def export
    deck = current_user.decks.includes(deck_cards: { card: [ :attacks, :abilities ] }).find(params[:id])
    exporter = params[:style] == "cardmarket" ? Decks::CardmarketExporter : Decks::Exporter
    render json: { text: exporter.call(deck) }
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

  private

  def deck_params
    params.require(:deck).permit(:name, :description)
  end
end
