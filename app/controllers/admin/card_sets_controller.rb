module Admin
  class CardSetsController < BaseController
    before_action :set_card_set, only: [ :show, :edit, :update, :destroy ]

    def index
      @card_sets = CardSet.by_release.includes(:cards)
      @pending_set_imports = Import.card_set_imports.pending
    end

    def show
      @cards = @card_set.cards.order(Arel.sql("CAST(set_number AS INTEGER)"))
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

    def import
      url = params[:url].to_s.strip
      if url.blank? || !url.start_with?("https://limitlesstcg.com/cards/")
        render json: { error: "Invalid Limitless URL." }, status: :unprocessable_entity
        return
      end

      set_code = url.split("/").last

      if Import.card_set_imports.pending.exists?(label: set_code)
        render json: { error: "Set #{set_code} is already being imported." }, status: :unprocessable_entity
        return
      end

      import = current_user.imports.create!(kind: "card_set", label: set_code)
      ::CardSets::ImportJob.perform_later(url, current_user, import)
      render json: { import_id: import.id, set_code: set_code }
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
