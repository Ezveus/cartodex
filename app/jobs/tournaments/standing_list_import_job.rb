module Tournaments
  # Imports the decklist a member typed into a standings row, as a Deck owned by nobody.
  #
  # Deliberately not Decks::ImportJob with a flag: that job broadcasts the finished deck into
  # #decks-grid and replaces #deck-count, which would file a tournament field list in the
  # contributor's own deck list — the one thing an ownerless deck must not be. Decks::Fetcher is
  # what the two legitimately share.
  #
  # Everything is broadcast to the *contributor's* :notifications stream, not the standing's or
  # the event's: they are the one person waiting for it, and they are the only one the layout
  # subscribes for.
  class StandingListImportJob < ApplicationJob
    def perform(standing, decklist, contributor, import)
      tournament = standing.tournament
      deck = ::Decks::Fetcher.call(
        decklist, nil, deck_name(standing, tournament),
        shared: true, format: tournament.format, standard_pool: tournament.standard_pool
      )
      standing.update!(deck: deck)
      import.update!(status: "completed")

      remove_importing_item(contributor, import)
      broadcast_flash(contributor, "flash-notice",
        %(Field list for "#{standing.player_name}" imported (#{deck.deck_cards.count} cards).))
      Turbo::StreamsChannel.broadcast_replace_to(
        contributor, :notifications,
        target: Tournaments::Standings::Row.dom_id(standing),
        # can_edit: the broadcast only ever reaches the contributor, who is signed in and may
        # therefore write any row — wiki governance, so no further question to ask.
        #
        # render_in(rails_view_context), not .call: Row uses link_to/button_to and route path
        # helpers, all of which delegate to a Rails view context (Phlex::Rails::Helpers::Routes'
        # URLOptions override calls it). A background job has no request to render one from, so
        # a fabricated one — a throwaway ApplicationController instance carrying a bare GET
        # request — is built for exactly this render. Decks::ImportJob's own broadcast avoids
        # the question entirely by giving Decks::DeckCard raw href attributes instead of
        # link_to; Row has no such escape hatch without changing a component this task does not
        # own, so the fabricated context is built here instead.
        html: Tournaments::Standings::Row.new(
          standing: standing, viewer: contributor, can_edit: true
        ).render_in(rails_view_context)
      )
    rescue => e
      import.update!(status: "failed", error_message: e.message)
      remove_importing_item(contributor, import)
      broadcast_flash(contributor, "flash-alert",
        %(Import of the field list for "#{standing.player_name}" failed: #{e.message}))
    end

    private

    # /decks/shared prints no author, so the name is the only thing that can situate the list.
    def deck_name(standing, tournament)
      "#{standing.player_name} — #{tournament.name} (#{tournament.date})"
    end

    # A minimal Rails view context, built the same way ActionController::Renderer builds one for
    # rendering a template outside a request (used by ActionMailer, previews, etc.) — a bare GET
    # request is all url_options and link_to/button_to need; nothing here reads session or
    # current_user.
    def rails_view_context
      request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/"))
      controller = ApplicationController.new
      controller.set_request!(request)
      controller.set_response!(ApplicationController.make_response!(request))
      controller.view_context
    end

    def remove_importing_item(contributor, import)
      Turbo::StreamsChannel.broadcast_remove_to(
        contributor, :notifications, target: "importing-#{import.id}"
      )
    end

    def broadcast_flash(contributor, css_class, message)
      Turbo::StreamsChannel.broadcast_append_to(
        contributor, :notifications, target: "flash-messages",
        html: <<~HTML
          <div class="flash #{css_class}" data-controller="flash">
            #{ERB::Util.html_escape(message)}
          </div>
        HTML
      )
    end
  end
end
