module Admin
  class StandardPoolsController < BaseController
    before_action :set_standard_pool, only: [ :edit, :update, :destroy ]

    def index
      # decks and tournaments are eager-loaded because the index shows their
      # counts: without them each row's `.size` would be its own COUNT query.
      # Same trade-off Admin::CardSetsController makes with `includes(:cards)`.
      @standard_pools = StandardPool
        .includes(:first_card_set, :last_card_set, :decks, :tournaments)
        .by_release
    end

    def new
      # A set release moves only the upper bound, so everything else is carried
      # over from the pool in force. The annual rotation is the one case where the
      # lower bound and the marks are typed in full.
      current = StandardPool.current
      @standard_pool = StandardPool.new(
        first_card_set_id: current&.first_card_set_id,
        regulation_marks: current&.regulation_marks
      )
    end

    def create
      @standard_pool = StandardPool.new(standard_pool_params)

      if @standard_pool.save
        redirect_to admin_standard_pools_path, notice: "Standard pool created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @standard_pool.update(standard_pool_params)
        redirect_to admin_standard_pools_path, notice: "Standard pool updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @standard_pool.destroy
        redirect_to admin_standard_pools_path, notice: "Standard pool deleted."
      else
        redirect_to admin_standard_pools_path, alert: @standard_pool.errors.full_messages.to_sentence
      end
    end

    private

    def set_standard_pool
      @standard_pool = StandardPool.find(params[:id])
    end

    def standard_pool_params
      permitted = params.require(:standard_pool)
        .permit(:first_card_set_id, :last_card_set_id, :regulation_marks, :released_on, :legal_on)

      # The form takes marks as free text ("H, I, J") because a fixed checkbox list
      # would need a deploy the first time a new mark is printed — the very thing
      # this screen exists to avoid.
      permitted.merge(regulation_marks: parse_marks(permitted[:regulation_marks]))
    end

    def parse_marks(value)
      return value if value.is_a?(Array)

      value.to_s.split(",").map { |mark| mark.strip.upcase }.reject(&:empty?)
    end
  end
end
