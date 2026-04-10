module Admin
  class CardsController < BaseController
    before_action :set_card, only: [ :show, :edit, :update, :rescrape ]

    def index
      @cards = Card.includes(:card_set).order(:name)
      @cards = @cards.where("name LIKE ?", "%#{params[:q]}%") if params[:q].present?
      @cards = @cards.limit(50)
    end

    def show; end

    def edit; end

    def update
      if @card.update(card_params)
        redirect_to admin_card_path(@card), notice: "Card updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def rescrape
      url = "https://limitlesstcg.com/cards/#{@card.set_name}/#{@card.set_number}"
      Cards::Fetcher.call(url)
      redirect_to admin_card_path(@card), notice: "Card rescraped."
    rescue => e
      redirect_to admin_card_path(@card), alert: "Rescrape failed: #{e.message}"
    end

    private

    def set_card
      @card = Card.find(params[:id])
    end

    def card_params
      params.require(:card).permit(:name, :card_type, :hp, :rarity, :type_symbol, :set_name, :set_number, :card_set_id)
    end
  end
end
