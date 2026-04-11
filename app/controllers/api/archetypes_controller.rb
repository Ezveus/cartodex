module Api
  class ArchetypesController < ApplicationController
    before_action :authenticate_user!

    def index
      q = params[:q].to_s.strip
      archetypes = if q.present?
        Archetype.search(q).includes(:primary_pokemon, :secondary_pokemon).limit(10)
      else
        Archetype.includes(:primary_pokemon, :secondary_pokemon).order(:name).limit(10)
      end

      render json: archetypes.map { |a| archetype_json(a) }
    end

    def create
      primary = Card.where(card_type: "Pokémon").find(params[:primary_pokemon_id])
      secondary = params[:secondary_pokemon_id].present? ? Card.where(card_type: "Pokémon").find(params[:secondary_pokemon_id]) : nil

      archetype = Archetype.find_or_initialize_by(
        primary_pokemon: primary,
        secondary_pokemon: secondary
      )

      if archetype.new_record?
        archetype.parent_id = params[:parent_id]
        archetype.save!
      end

      render json: archetype_json(archetype), status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Pokemon not found" }, status: :not_found
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    def archetype_json(a)
      {
        id: a.id,
        name: a.name,
        primary_pokemon: a.primary_pokemon.name,
        secondary_pokemon: a.secondary_pokemon&.name,
        parent_id: a.parent_id
      }
    end
  end
end
