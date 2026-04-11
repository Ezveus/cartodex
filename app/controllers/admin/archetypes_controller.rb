module Admin
  class ArchetypesController < BaseController
    before_action :set_archetype, only: [ :show, :edit, :update, :destroy ]

    def index
      @archetypes = Archetype.includes(:primary_pokemon, :secondary_pokemon, :parent, :children).order(:name)
    end

    def show; end

    def new
      @archetype = Archetype.new
    end

    def create
      @archetype = Archetype.new(archetype_params)
      @archetype.custom_name = params[:archetype][:name] if params[:archetype][:name].present?

      if @archetype.save
        redirect_to admin_archetype_path(@archetype), notice: "Archetype created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      @archetype.custom_name = params[:archetype][:name] if params[:archetype][:name].present?

      if @archetype.update(archetype_params)
        redirect_to admin_archetype_path(@archetype), notice: "Archetype updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @archetype.destroy
      redirect_to admin_archetypes_path, notice: "Archetype deleted."
    end

    private

    def set_archetype
      @archetype = Archetype.find(params[:id])
    end

    def archetype_params
      params.require(:archetype).permit(:name, :primary_pokemon_id, :secondary_pokemon_id, :parent_id)
    end
  end
end
