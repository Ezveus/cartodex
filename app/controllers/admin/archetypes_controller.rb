module Admin
  class ArchetypesController < BaseController
    before_action :set_archetype, only: [ :show, :edit, :update, :destroy ]

    def index
      @archetypes = Archetype.includes(:primary_card, :secondary_card, :parent, :children).order(:name)
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
      if @archetype.destroy
        redirect_to admin_archetypes_path, notice: "Archetype deleted."
      else
        # restrict_with_error's own message names the association, not what a reader needs to
        # know, which is what is in the way and how much of it.
        count = @archetype.tournament_standings.count
        redirect_to admin_archetype_path(@archetype),
          alert: "This archetype is still named on #{count} tournament #{"standing".pluralize(count)}."
      end
    end

    private

    def set_archetype
      @archetype = Archetype.find(params[:id])
    end

    def archetype_params
      params.require(:archetype).permit(:name, :primary_card_id, :secondary_card_id, :parent_id)
    end
  end
end
