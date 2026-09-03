class HomeController < ApplicationController
  include PubliclyReachable

  publicly_reachable :dashboard

  SHOWCASE_LIMIT = 6

  def dashboard
    authorize :dashboard, :show?
    @pending_deck_imports = current_user ? current_user.imports.deck_imports.pending : []
    # to_a for the same reason as DecksController#shared: the view asks `any?` before
    # iterating, which on an unloaded relation is an extra existence probe.
    @shared_decks = Deck.shared.order(created_at: :desc).limit(SHOWCASE_LIMIT)
                        .with_standard_pool
                        .includes(archetype: [ :primary_card, :secondary_card ]).to_a
  end

  private

  # The dashboard renders Search::Spotlight itself, right under the welcome line.
  def search_overlay?
    false
  end
end
