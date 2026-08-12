module Api
  class CollectionsController < ApplicationController
    before_action :authenticate_user!

    def index
      collections = current_user.collections.includes(:card).load
      total_cards = collections.sum(&:quantity)
      # Batched: collection_json used to compute availability per row, an N+1
      # that grew with the user's collection.
      availability = Allocations::Availability.for_cards(user: current_user, cards: collections.map(&:card))

      render json: {
        collections: collections.map { |c| collection_json(c, availability[c.card_id]) },
        total_cards: total_cards
      }
    end

    def create
      card = Card.find(collection_params[:card_id])
      collection = Collections::CardAdder.call(user: current_user, card: card, quantity: collection_params[:quantity].to_i)
      render json: collection_json(collection), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      card = Card.find(params[:id])
      collection = Collections::QuantitySetter.call(user: current_user, card: card, quantity: collection_params[:quantity].to_i)
      render json: collection_json(collection)
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def destroy
      collection = current_user.collections.find_by!(card_id: params[:id])
      collection.destroy

      head :no_content
    end

    private

    def collection_params
      params.require(:collection).permit(:card_id, :quantity)
    end

    # `availability` is passed in so a caller rendering many rows can resolve it
    # in one batch; single-record actions let it default.
    def collection_json(collection, availability = nil)
      availability ||= Allocations::Availability.call(user: current_user, card: collection.card)
      {
        id: collection.id,
        card_id: collection.card_id,
        quantity: collection.quantity,
        owned: availability.owned,
        committed: availability.committed,
        available: availability.available,
        card: {
          name: collection.card.name,
          card_type: collection.card.card_type,
          set_name: collection.card.set_name,
          set_number: collection.card.set_number,
          rarity: collection.card.rarity,
          hp: collection.card.hp,
          type_symbol: collection.card.type_symbol
        }
      }
    end
  end
end
