module Api
  class CollectionsController < ApplicationController
    before_action :authenticate_user!

    def index
      collections = current_user.collections.includes(:card)
      total_cards = collections.sum(:quantity)

      render json: {
        collections: collections.map { |c| collection_json(c) },
        total_cards: total_cards
      }
    end

    def create
      collection = current_user.collections.find_or_initialize_by(card_id: collection_params[:card_id])
      collection.quantity = collection.quantity.to_i + collection_params[:quantity].to_i

      if collection.save
        render json: collection_json(collection), status: :created
      else
        render json: { errors: collection.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      collection = current_user.collections.find_by!(card_id: params[:id])

      if collection.update(collection_params)
        render json: collection_json(collection)
      else
        render json: { errors: collection.errors.full_messages }, status: :unprocessable_entity
      end
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

    def collection_json(collection)
      {
        id: collection.id,
        card_id: collection.card_id,
        quantity: collection.quantity,
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
