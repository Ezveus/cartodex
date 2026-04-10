module Admin
  class DashboardController < BaseController
    def index
      @user_count = User.count
      @card_count = Card.count
      @deck_count = Deck.count
      @set_count = CardSet.count
      @recent_users = User.order(created_at: :desc).limit(5)
      @recent_decks = Deck.includes(:user).order(created_at: :desc).limit(5)
    end
  end
end
