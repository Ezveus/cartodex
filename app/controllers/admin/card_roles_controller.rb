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

      scope = filtered_cards
      @pages = (scope.distinct.count(:fingerprint) / PER_PAGE.to_f).ceil
      @page = [ params[:page].to_s.to_i, 1 ].max.clamp(1, [ @pages, 1 ].max)
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

      ticked = Array(params[:roles]).map(&:to_s)
      decide(fingerprint, card, ticked)

      @roles = CardLabel.roles.to_a
      @row = row_for(card, fingerprint)
      @assignments = assignments_for([ fingerprint ])
      render :update
    end

    # Inline rather than a job, unlike the label import beside it: this makes no HTTP request and
    # reads text the catalogue already holds — measured at 1.8 s for all 3023 fingerprints,
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

    Row = Struct.new(:fingerprint, :card, keyword_init: true)

    def played_filter
      return DEFAULT_PLAYED unless params.key?(:played)

      ActiveModel::Type::Boolean.new.cast(params[:played]).present?
    end

    def filter_params
      { q: params[:q].presence, card_type: params[:card_type].presence,
        played: (params[:played] if params.key?(:played)), page: params[:page].presence }.compact
    end

    def filtered_cards
      scope = Card.all
      scope = scope.where("cards.name LIKE ?", "%#{Card.sanitize_sql_like(@query)}%") if @query.present?
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
    def rows_for(scope)
      grouped = scope.where.not(fingerprint: [ nil, "" ])
                     .group(:fingerprint)
                     .order(Arel.sql("MIN(cards.name)"))
                     .offset((@page - 1) * PER_PAGE)
                     .limit(PER_PAGE)
                     .pluck(Arel.sql("cards.fingerprint"), Arel.sql("MAX(cards.id)"))

      cards = Card.where(id: grouped.map(&:last)).index_by(&:id)
      grouped.map { |fingerprint, card_id| Row.new(fingerprint: fingerprint, card: cards[card_id]) }
    end

    def row_for(card, fingerprint)
      Row.new(fingerprint: fingerprint, card: card)
    end

    # (fingerprint, card_label_id) -> the assignment, so a row asks a Hash and not the database.
    def assignments_for(fingerprints)
      CardLabelAssignment.where(fingerprint: fingerprints, card_label_id: CardLabel.roles.select(:id))
                         .index_by { |assignment| [ assignment.fingerprint, assignment.card_label_id ] }
    end

    def decide(fingerprint, card, ticked)
      labels = CardLabel.roles.to_a

      CardLabelAssignment.transaction do
        labels.each do |label|
          assignment = CardLabelAssignment.find_or_initialize_by(card_label: label, fingerprint: fingerprint)
          assignment.update!(source: "curated", rejected: ticked.exclude?(label.slug), card: card)
        end
      end
    end
  end
end
