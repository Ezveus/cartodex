class HomeController < ApplicationController
  include PubliclyReachable

  publicly_reachable :dashboard

  SHOWCASE_LIMIT = 6

  def dashboard
    authorize :dashboard, :show?
    @pending_deck_imports = current_user ? current_user.imports.deck_imports.pending : []
    # Both bounds of the pool, not just the pool: the format badge names it from
    # StandardPool#name, which reads them — three extra queries per Standard deck otherwise.
    @shared_decks = Deck.shared.order(created_at: :desc).limit(SHOWCASE_LIMIT)
                        .includes(archetype: [ :primary_card, :secondary_card ],
                                  standard_pool: [ :first_card_set, :last_card_set ])
  end
end
