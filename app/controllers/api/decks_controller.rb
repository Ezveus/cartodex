module Api
  class DecksController < ApplicationController
    before_action :authenticate_user!
    before_action :set_deck, only: [ :show, :update, :destroy, :suggested_archetype ]

    def index
      decks = current_user.decks.includes(:deck_cards, :cards)
      render json: decks.map { |deck| deck_json(deck) }
    end

    def show
      render json: deck_json(@deck)
    end

    def create
      # The API cannot declare a format (deck_params permits neither :format nor
      # :standard_pool_id), so a deck created through it is always Standard by the
      # column default. Anchor it to the current pool rather than leave it
      # unsavable: the API has no business choosing which Standard, only whether
      # one gets picked for it.
      deck = current_user.decks.build(deck_params.reverse_merge(standard_pool: StandardPool.current))

      if deck.save
        render json: deck_json(deck), status: :created
      else
        render json: { errors: deck.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def import
      import = current_user.imports.create!(kind: "deck", label: params[:name])
      Decks::ImportJob.perform_later(params[:decklist], current_user, params[:name], import)
      render json: { import_id: import.id }, status: :accepted
    end

    def update
      if @deck.update(deck_params)
        render json: deck_json(@deck)
      else
        render json: { errors: @deck.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # Infers the deck's archetype from its line-up: either an existing archetype
    # to select, or candidate Pokémon to pre-fill the "create archetype" form.
    def suggested_archetype
      detection = Decks::ArchetypeDetector.call(@deck)

      if detection.matched?
        render json: { matched: true, archetype: archetype_json(detection.archetype) }
      elsif detection.suggested_primary
        render json: {
          matched: false,
          suggested_primary: card_json(detection.suggested_primary),
          suggested_secondary: card_json(detection.suggested_secondary)
        }
      else
        render json: { matched: false }
      end
    end

    def destroy
      @deck.destroy
      head :no_content
    end

    private

    def set_deck
      @deck = current_user.decks.includes(deck_cards: { card: :pokemon_subtype }).find_by!(key: params[:id])
    end

    def archetype_json(archetype)
      {
        id: archetype.id,
        name: archetype.name,
        primary_card: card_json(archetype.primary_card),
        secondary_card: card_json(archetype.secondary_card)
      }
    end

    def card_json(card)
      return nil if card.nil?

      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number }
    end

    def deck_params
      params.require(:deck).permit(:name, :description)
    end

    def deck_json(deck)
      {
        id: deck.id,
        name: deck.name,
        description: deck.description,
        physical: deck.physical,
        tcg_live: deck.tcg_live,
        cards: deck.deck_cards.map { |dc| deck_card_json(dc) }
      }
    end

    def deck_card_json(deck_card)
      {
        id: deck_card.id,
        quantity: deck_card.quantity,
        owned_copies: deck_card.owned_copies,
        proxies: deck_card.proxies,
        card: {
          id: deck_card.card.id,
          name: deck_card.card.name,
          card_type: deck_card.card.card_type,
          set_name: deck_card.card.set_name,
          set_number: deck_card.card.set_number,
          rarity: deck_card.card.rarity,
          hp: deck_card.card.hp,
          type_symbol: deck_card.card.type_symbol
        }
      }
    end
  end
end
