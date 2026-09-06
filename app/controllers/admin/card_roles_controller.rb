module Admin
  # Where a human decides what a card *does*. CardLabels::RoleSuggester proposes; this screen is
  # the only thing that writes a `curated` row, and a `curated` row is what the suggester will
  # never examine again.
  #
  # No Pundit call: Admin::BaseController#require_admin! is the whole gate for this namespace.
  #
  # One row per **fingerprint**, not per printing — a label is about the card, and offering
  # budew_pre and budew_asc as two rows would offer a second checkbox for a decision already made.
  # The representative printing is the highest `cards.id` of the group, the same "most recently
  # learned printing" the suggester writes into `card_id`.
  class CardRolesController < BaseController
    PER_PAGE = 50

    # The filter that makes the first pass an evening's work: measured on the production dump the
    # catalogue holds 3023 fingerprints and the recorded lists play 94 of them. It is the default
    # because curating what nobody plays is work no reader of the report will ever see — and the
    # screen says so rather than leaving the reader to discover a filter is on.
    DEFAULT_PLAYED = true

    def index
      @roles = CardLabel.roles.to_a
      @played = played_filter
      @query = params[:q].to_s.strip
      @card_type = params[:card_type].to_s.presence

      filters
      scope = filtered_cards
      # Counted over the same population rows_for renders: SQL's COUNT ignores NULL but counts an
      # empty string, and a blank fingerprint is listed separately rather than paged.
      @pages = (labellable(scope).distinct.count(:fingerprint) / PER_PAGE.to_f).ceil
      # `to_s` before `to_i` because `?page[]=1` hands an Array and `?page[a]=b` an
      # ActionController::Parameters, and neither answers to_i — the clamp ArchetypesController
      # and TournamentsController each spell out for themselves.
      @page = params[:page].to_s.to_i.clamp(1, [ @pages, 1 ].max)
      @rows = rows_for(scope)
      @assignments = assignments_for(@rows.map(&:fingerprint))
      # A card with no fingerprint can never be labelled — an assignment would name a key no card
      # carries and the report could never join it. It is listed anyway, on the first page, with
      # its boxes disabled: a click the screen could not write must not be offered. Zero such
      # cards exist today, and this row is what stops that becoming an assumption.
      @unfingerprinted = @page == 1 ? filtered_cards.where(fingerprint: [ nil, "" ]).order(:name).to_a : []
    end

    # A save is a statement about the whole card and not about the box that moved: every role left
    # unticked becomes a recorded refusal, which is exactly what stops the next suggester run
    # re-proposing the six the human just said no to. Nothing is ever deleted here — a deletion
    # would read as "nobody has looked at this yet", which is the one thing that is no longer true.
    def update
      fingerprint = params[:id].to_s
      card = Card.where(fingerprint: fingerprint).order(:id).last
      return head :not_found if card.nil?

      ::CardLabels::RoleDecision.call(fingerprint: fingerprint, card: card, ticked: params[:roles])

      @roles = CardLabel.roles.to_a
      @card = card
      @assignments = assignments_for([ fingerprint ])

      # Branched, because only the Turbo Stream template exists: an unbranched Accept: text/html
      # request raises MissingTemplate *after* the seven rows have committed, which is the
      # DecksController#share lesson. The form is fired by Stimulus and Turbo intercepts it, so
      # this is the path a client without Turbo takes — it must land somewhere, not 500 over a
      # decision that was in fact recorded.
      respond_to do |format|
        format.turbo_stream { render :update }
        format.html { redirect_to admin_card_roles_path(filter_params), notice: "Roles saved." }
      end
    end

    # "I have no opinion about this card after all." A save decides all seven roles at once, so
    # one misclick otherwise removes a card from the suggester's reach permanently — and nothing
    # else in the app deletes an assignment. It is deliberately a separate, explicit action:
    # deleting *here* is a request, while deleting when a box is unticked would erase a refusal,
    # which is the one thing the store exists to keep.
    def destroy
      fingerprint = params[:id].to_s
      card = Card.where(fingerprint: fingerprint).order(:id).last
      return head :not_found if card.nil?

      CardLabelAssignment.curated.where(fingerprint: fingerprint).destroy_all

      @roles = CardLabel.roles.to_a
      @card = card
      @assignments = assignments_for([ fingerprint ])

      respond_to do |format|
        format.turbo_stream { render :update }
        format.html { redirect_to admin_card_roles_path(filter_params), notice: "Decisions cleared." }
      end
    end

    # "I have no opinion about this card after all." A save decides all seven roles at once, so one
    # misclick otherwise removes a card from the suggester's reach permanently — and nothing else
    # in the app deletes an assignment. It is deliberately a separate, explicit action: deleting
    # *here* is a request, while deleting when a box is unticked would erase a refusal, which is
    # the one thing the store exists to keep.
    def destroy
      fingerprint = params[:id].to_s
      card = Card.where(fingerprint: fingerprint).order(:id).last
      return head :not_found if card.nil?

      CardLabelAssignment.curated.where(fingerprint: fingerprint).destroy_all

      @roles = CardLabel.roles.to_a
      @card = card
      @assignments = assignments_for([ fingerprint ])

      respond_to do |format|
        format.turbo_stream { render :update }
        format.html { redirect_to admin_card_roles_path(filter_params), notice: "Decisions cleared." }
      end
    end

    # Inline rather than a job, unlike the label import beside it: this makes no HTTP request and
    # reads text the catalogue already holds — measured at 1.2 s for all 3023 fingerprints,
    # writing 714 suggestions.
    def suggest
      result = ::CardLabels::RoleSuggester.call

      redirect_to admin_card_roles_path(filter_params),
        notice: "#{result.created} #{"suggestion".pluralize(result.created)} added, " \
                "#{result.kept} kept, #{result.withdrawn} withdrawn, " \
                "#{result.decided} decided by hand left alone."
    rescue ::CardLabels::RoleSuggester::MissingRoles => error
      redirect_to admin_card_roles_path(filter_params), alert: error.message
    end

    private

    def played_filter
      return DEFAULT_PLAYED unless params.key?(:played)

      ActiveModel::Type::Boolean.new.cast(params[:played]).present?
    end

    # One hash, three readers: the view's filter bar, the pager's links and the redirect after a
    # suggestion run. `played` rides only when it was asked for, so a redirect never writes the
    # default into the URL.
    def filters
      @filters ||= { q: @query.presence, card_type: @card_type, played: @played }.compact
    end

    def filter_params
      filters.merge(page: params[:page].presence).compact
    end

    def filtered_cards
      scope = Card.all
      # Card.name_matching, not a LIKE spelled out here: the concern searches `name_normalized`
      # (SQLite folds ASCII only, so an accented name in the wrong case is otherwise unfindable),
      # carries the ESCAPE clause a typed `%` needs, and caps the pattern's length.
      scope = scope.merge(Card.name_matching(@query)) if @query.present?
      scope = scope.where(card_type: @card_type) if @card_type
      scope = scope.where(id: played_card_ids) if @played
      scope
    end

    def played_card_ids
      DeckCard.where(deck_id: TournamentStanding.where.not(deck_id: nil).select(:deck_id)).select(:card_id)
    end

    # One grouped read for the page: the fingerprint, the name it sorts under, and the id of the
    # printing that represents it. Reading the printings row by row is the obvious way to write
    # this screen and is what would make its cost grow with the page.
    def labellable(scope) = scope.where.not(fingerprint: [ nil, "" ])

    def rows_for(scope)
      grouped = labellable(scope)
                     .group(:fingerprint)
                     .order(Arel.sql("MIN(cards.name)"))
                     .offset((@page - 1) * PER_PAGE)
                     .limit(PER_PAGE)
                     .pluck(Arel.sql("cards.fingerprint"), Arel.sql("MAX(cards.id)"))

      Card.where(id: grouped.map(&:last)).to_a.sort_by { |card| card.name.downcase }
    end

    # (fingerprint, card_label_id) -> the assignment, so a row asks a Hash and not the database.
    def assignments_for(fingerprints)
      CardLabelAssignment.where(fingerprint: fingerprints, card_label_id: CardLabel.roles.select(:id))
                         .index_by { |assignment| [ assignment.fingerprint, assignment.card_label_id ] }
    end
  end
end
