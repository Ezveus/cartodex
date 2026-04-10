module Admin
  class CardSetsController < BaseController
    before_action :set_card_set, only: [ :show, :edit, :update, :destroy ]

    def index
      @card_sets = CardSet.by_release.includes(:cards)
    end

    def show
      @cards = @card_set.cards.order(:set_number)
    end

    def new
      @card_set = CardSet.new
    end

    def create
      @card_set = CardSet.new(card_set_params)
      if @card_set.save
        redirect_to admin_card_set_path(@card_set), notice: "Card set created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @card_set.update(card_set_params)
        redirect_to admin_card_set_path(@card_set), notice: "Card set updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @card_set.destroy
      redirect_to admin_card_sets_path, notice: "Card set deleted."
    end

    private

    def set_card_set
      @card_set = CardSet.find(params[:id])
    end

    def card_set_params
      params.require(:card_set).permit(:code, :name, :block_name, :release_date, :logo_url)
    end
  end
end
