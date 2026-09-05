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
    # The standing was deleted while this job waited in the queue. A real failure of the import,
    # reported down the same path as a bad decklist — see #perform for why it cannot be an
    # ActiveJob::DeserializationError instead.
    class StandingDeleted < StandardError; end

    # Ids, not records, unlike Decks::ImportJob and CardSets::ImportJob. Those two are handed a
    # user and an import, neither of which can disappear while the job waits. Standings are
    # wiki-governed: any member may delete this row, or the event, which cascades onto it. Passed
    # as records, GlobalID would then fail to deserialize and raise *before* #perform is entered,
    # where no rescue of this method can see it — the Import row would sit at "pending" forever,
    # with Admin::ImportsController#retry refusing this kind and nothing else able to clear it. As
    # ids, the deletion is an ordinary lookup miss and reports itself like any other failure.
    def perform(standing_id, decklist, contributor_id, import_id)
      import = Import.find_by(id: import_id)
      contributor = User.find_by(id: contributor_id)
      # Nothing left to report to, or about. A destroyed user takes their imports with them, so
      # this is the same event seen from either side.
      return if import.nil? || contributor.nil?

      standing = TournamentStanding.find_by(id: standing_id)
      raise StandingDeleted, "the standing was deleted before its list could be imported" if standing.nil?

      tournament = standing.tournament
      # The raw id, not standing.deck: Rails auto-detects the inverse of this belongs_to/has_one
      # pair, so loading the association here would cache `standing` as *this* deck's
      # tournament_standing — and dependent: :nullify below would then nullify that cached
      # target (the same in-memory `standing`, already pointed at the *new* deck by the time it
      # runs) instead of requerying, undoing the update! two lines down. Re-fetching the deck by
      # id after the update sidesteps that entirely.
      previous_deck_id = standing.deck_id
      deck = ::Decks::Fetcher.call(
        decklist, nil, deck_name(standing, tournament),
        shared: true, format: tournament.format, standard_pool: tournament.standard_pool,
        # Not optional alongside format: a deck whose format is "other" and whose custom name is
        # blank fails validation, and "other" is a format the event form really offers.
        other_format_name: tournament.other_format_name
      )
      standing.update!(deck: deck)
      # The standing points at the new deck before the old one is destroyed, never the other way
      # round, so it is never left pointing at a destroyed row. destroy_if_ownerless is the same
      # guard TournamentStanding#destroy_ownerless_deck applies on delete: nothing points a
      # standing at a member's own deck today, but a re-import must not be the caller that
      # detonates one if that ever changes. Without this, re-importing over an existing field
      # list would leave the old Deck referenced by nothing — still shared: true, so listed at
      # /decks/shared and in every spotlight, under a name byte-identical to the new one, forever
      # (no path in the app can reach an ownerless deck to delete it any other way).
      Deck.find_by(id: previous_deck_id)&.destroy_if_ownerless
      import.update!(status: "completed")

      broadcast_success(standing, deck, contributor, import)
    rescue => e
      discard_orphaned_list(deck, standing_id)
      import.update!(status: "failed", error_message: e.message)
      remove_importing_item(contributor, import)
      broadcast_flash(contributor, "flash-alert",
        %(Import of the field list for "#{import.label}" failed: #{e.message}))
    end

    private

    # Decks::Fetcher commits its own transaction, so a deck can land and the update! attaching it
    # still fail — the standing deleted underneath us, or gone invalid since it was written (the
    # event's field sizes are editable and cap a placement already recorded). What is left is
    # exactly the orphan the re-import path guards against above: an ownerless, shared Deck
    # referenced by nothing, listed at /decks/shared and in every spotlight, with no path in the
    # app able to reach it. `deck` is nil whenever Fetcher itself raised, which is the common case.
    #
    # The column is read back from the database rather than off the record: update! assigns the
    # association before it validates, so a *failed* standing.update!(deck: deck) leaves
    # standing.deck_id pointing at this deck in memory while nothing was written.
    def discard_orphaned_list(deck, standing_id)
      return if deck.nil?
      return if TournamentStanding.where(id: standing_id).pick(:deck_id) == deck.id

      deck.destroy_if_ownerless
    end

    # /decks/shared prints no author, so the name is the only thing that can situate the list.
    def deck_name(standing, tournament)
      "#{standing.player_name} — #{tournament.name} (#{tournament.date})"
    end

    # The import's work is the deck: it is created and *attached to the standing* above, before
    # this method ever runs. Everything here is a notification about that work, not the work
    # itself, so a failure in here must never flip a completed import back to "failed" — the
    # outer rescue exists for Decks::Fetcher raising or a bad decklist, not for a broadcast that
    # merely failed to tell the page about a deck that already landed. Logged rather than
    # silently swallowed: the contributor's page will just not update until they reload.
    #
    # Since the sheet is paginated, the replace is also a no-op whenever the row is not on the page
    # the contributor happens to be looking at — Turbo finds no element and does nothing, while the
    # "Importing…" item (importing-<import id>, rendered on every page) still clears and the flash
    # still fires. The common case is covered by the redirect after #create, which lands the member
    # on the row's own page; the rest is a reload of the right page away.
    def broadcast_success(standing, deck, contributor, import)
      remove_importing_item(contributor, import)
      broadcast_flash(contributor, "flash-notice",
        %(Field list for "#{standing.player_name}" imported (#{deck.deck_cards.count} cards).))
      Turbo::StreamsChannel.broadcast_replace_to(
        contributor, :notifications,
        target: Tournaments::Standings::Row.dom_id(standing),
        # can_edit: the broadcast only ever reaches the contributor, who is signed in and may
        # therefore write any row — wiki governance, so no further question to ask.
        #
        # claimable_entries is passed rather than left at Row's [] default: this replaces the row
        # wholesale, and a contributor who has an unrecorded participation at this event was
        # looking at a "This is me" button on it. Rendering the replacement without them deleted
        # that button until the next reload.
        #
        # The row's `button_to` (claim/unclaim, delete) carries no authenticity token here: this
        # is rendered by ApplicationController.renderer, not inside the request whose CSRF
        # session the token would need to match anyway. It works in the browser because Turbo
        # intercepts the form submission and replaces X-CSRF-Token with the value from the *live
        # page's* own <meta name="csrf-token"> before sending it, and Rails' verified_request?
        # accepts that header — the hidden field's stale value is never actually checked. If
        # Turbo ever stopped doing that (or a client submitted the form without Turbo), these
        # buttons would 422 with an invalid authenticity token. Not fixed here: injecting a real
        # token would need a real session, and there is no session to borrow one from outside a
        # request — this is a case to exercise by clicking a live-broadcasted button in a
        # browser, not something a render-context change can paper over.
        #
        # render_in via ApplicationController.renderer, not .call: Row uses link_to/button_to and
        # route path helpers. Rails' url_for consults url_options even for a bare _path helper,
        # and Phlex::Rails::Helpers::Routes overrides url_options/default_url_options to delegate
        # to the component's view_context — which is nil outside a real render_in(view_context)
        # call, hence the NoMethodError a plain .call raises here. (Route helpers mixed in
        # directly, as Rails.application.routes.url_helpers.deck_path is called in
        # Decks::DeckCard, do *not* hit this: called that way, self is the url_helpers module,
        # not the component, so the overridden url_options is never consulted — that plus
        # with_actions: false, which keeps link_to/button_to from running at all, is how
        # Decks::ImportJob's broadcast avoids the question entirely.) ApplicationController's
        # own renderer builds exactly the request-shaped context render_in needs and additionally
        # resolves url_options from the app's configured default_url_options
        # (config/application.rb) rather than Rack's bare "example.org" default — verified to
        # produce byte-identical output to a hand-built view context for this component, so it is
        # strictly better with no downside for the _path helpers Row actually uses.
        html: ApplicationController.renderer.render(
          Tournaments::Standings::Row.new(
            standing: standing, viewer: contributor, can_edit: true,
            claimable_entries: claimable_entries(standing, contributor)
          ),
          layout: false
        )
      )
    rescue => e
      Rails.logger.error(
        "Tournaments::StandingListImportJob: broadcast for import #{import.id} failed: #{e.message}"
      )
    end

    # The contributor's own participations at this event that no standing names yet — the same
    # question TournamentsController#show asks, answered the same way, so a row this job renders
    # offers exactly the buttons a reload would.
    def claimable_entries(standing, contributor)
      contributor.tournament_entries
        .where(tournament_id: standing.tournament_id)
        .includes(:tournament_profile, :standing)
        .order(:id)
        .reject(&:standing)
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
