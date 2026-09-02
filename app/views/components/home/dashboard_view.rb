module Home
  class DashboardView < ApplicationComponent
    def initialize(current_user:, shared_decks:, pending_deck_imports: [])
      @current_user = current_user
      @shared_decks = shared_decks
      @pending_deck_imports = pending_deck_imports
    end

    def view_template
      # The `decks` controller belongs to the signed-in page only: its connect() fetches
      # /api/decks for the deck count, and for a visitor that request is a redirect to sign-in
      # whose HTML body dies in response.json() — a console error on every visit.
      div(class: "dashboard-container", data: (@current_user ? { controller: "decks" } : nil)) do
        if @current_user
          # The only place on this page that prints an email — decision 7 forbids one on a
          # public surface, so it lives inside this branch rather than above it.
          h1 { "Welcome, #{@current_user.email}" }
        else
          h1 { "Cartodex" }
          p { "Your Pokémon Trading Card Game Manager" }
        end

        render Search::Spotlight.new

        if @current_user
          signed_in_grid
        else
          visitor_call_to_action
        end

        showcase if @shared_decks.any?

        if @current_user
          render Ui::DeckImport.new(pending_imports: @pending_deck_imports)
          scanner_modal
        end
      end
    end

    private

    def signed_in_grid
      div(class: "dashboard-grid") do
        collection_card
        decks_card
      end
    end

    def visitor_call_to_action
      div(class: "auth-buttons") do
        link_to "Sign In", new_user_session_path, class: "btn btn-primary"
        link_to "Sign Up", new_user_registration_path, class: "btn btn-secondary"
      end
    end

    def showcase
      section(class: "dashboard-showcase") do
        h2 { "Recently shared decks" }
        div(class: "dashboard-showcase-grid") do
          @shared_decks.each do |deck|
            link_to deck.name, deck_path(deck), class: "dashboard-showcase-deck"
          end
        end
        link_to "See all shared decks", shared_decks_path, class: "btn btn-secondary btn-sm"
      end
    end

    def collection_card
      div(class: "dashboard-card", data: { controller: "collection" }) do
        h2 { "My Collection" }
        div(class: "card-count") do
          span(data: { collection_target: "count" }) { "0" }
          plain " cards"
        end
        div(class: "card-actions") do
          link_to "View Collection", collections_path, class: "btn btn-primary"
          link_to "Scan Card", "#", class: "btn btn-secondary", data: { action: "collection#openScanner" }
        end
      end
    end

    def decks_card
      div(class: "dashboard-card") do
        h2 { "My Decks" }
        div(class: "deck-count") do
          span(id: "deck-count", data: { decks_target: "count" }) { "0" }
          plain " decks"
        end
        div(class: "deck-actions") do
          link_to "View Decks", decks_path, class: "btn btn-primary"
          link_to "Create Deck", new_deck_path, class: "btn btn-secondary"
          link_to "Import Deck", "#", class: "btn btn-secondary", data: { action: "decks#openImport" }
        end
      end
    end

    def scanner_modal
      render Ui::Modal.new(id: "scanner-modal", title: "Scan Card", collection_target: "scannerModal") do
        video(id: "scanner-video", data: { collection_target: "video" })
        button(class: "btn btn-secondary", data: { action: "collection#closeScanner" }) { "Close" }
      end
    end
  end
end
