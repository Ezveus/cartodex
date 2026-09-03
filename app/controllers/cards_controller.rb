class CardsController < ApplicationController
  include CardSearchable
  include PubliclyReachable

  publicly_reachable :index, :show, :image

  PER_PAGE = 48

  # The proxy fetches from limitlesstcg.com on every request — #image caches no bytes, so
  # expires_in is a response header and nothing more. Absent a shared cache in front, one
  # inbound request is one outbound request to a third party.
  #
  # 300/min is derived, not copied. The proxy serves exactly two things, the deck page's hover
  # preview and the image export (/cards and /cards/:id hotlink card.image_url directly), and
  # the export loads every printing of a deck in parallel. A deck holds at most 60 cards, so
  # one export is at most 60 requests: 300/min leaves five exports a minute per IP. Copying
  # Mcp::ServerController's 30/min would have broken the second export of the minute — an
  # export the public scope explicitly promises.
  IMAGE_RATE_LIMIT_TO = 300
  INDEX_RATE_LIMIT_TO = 60
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: IMAGE_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "cards-image", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :image

  rate_limit to: INDEX_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "cards-index", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :index

  def index
    authorize Card, :index?
    @blocks = CardSet.by_release.group_by(&:block_name)
    # A count per set, not every Card in the database. The sidebar prints these numbers and
    # nothing else on the page reads the cards themselves.
    @card_counts = Card.group(:card_set_id).count
    @current_set = CardSet.find_by(code: params[:set]) if params[:set].present?

    @query  = params[:q].to_s.strip
    @type   = params[:type].presence
    @energy = params[:energy].presence
    @rarity = params[:rarity].presence
    @mark   = params[:mark].presence
    # to_s first: a Hash- or Array-shaped `page` param answers to neither to_i nor the
    # concern's two rescued exceptions, and this action is reachable without a session.
    @page   = [ params[:page].to_s.to_i, 1 ].max

    @searching = @query.length >= 2 || @type || @energy || @rarity || @mark

    # Both lists change only when a set is imported, and neither `rarity` nor
    # `regulation_mark` is indexed — two full scans of `cards` on every request, anonymous
    # ones included, once this action is public. A cache is the honest fix here: an index on a
    # low-cardinality column read on every page load is not.
    cache_key = [ "cards/filter-values", Card.maximum(:updated_at)&.to_i ]
    @rarities, @marks = Rails.cache.fetch(cache_key) do
      [
        Card.where.not(rarity: [ nil, "" ]).distinct.order(:rarity).pluck(:rarity),
        Card.where.not(regulation_mark: [ nil, "" ]).distinct.order(:regulation_mark).pluck(:regulation_mark)
      ]
    end

    @cards =
      if @searching
        scope = filtered_scope
        @total = scope.count
        @pages = (@total / PER_PAGE.to_f).ceil
        scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      elsif @current_set
        @current_set.cards.order(Arel.sql("CAST(set_number AS INTEGER)"))
      else
        Card.none
      end
  end

  def show
    @card = Card.includes(:attacks, :abilities, :pokemon_subtype).find(params[:id])
    authorize @card
    @alt_printings = Card.where(name: @card.name, fingerprint: @card.fingerprint)
                         .where.not(id: @card.id)
                         .order(:set_name)
    @collection_quantity = current_user&.collections&.find_by(card_id: @card.id)&.quantity.to_i
  end

  def image
    card = Card.find(params[:id])
    authorize card, :image?
    return head :not_found if card.image_url.blank?

    begin
      body = HttpFetcher.call(card.image_url)
    rescue HttpFetcher::FetchError => e
      Rails.logger.warn "Image proxy failed for card #{card.id}: #{e.message}"
      return head :bad_gateway
    end

    # Not a secret, and a shared cache in front of the app is the only thing that can make
    # this endpoint cheap.
    expires_in 30.days, public: true
    send_data body, type: image_content_type(card.image_url), disposition: "inline"
  end

  private

  def filtered_scope
    scope = Card.all
    scope = scope.where(card_set_id: @current_set.id) if @current_set
    scope = apply_card_name_filter(scope, @query) if @query.length >= 2
    scope = scope.where(card_type: @type) if @type
    scope = scope.where(type_symbol: @energy) if @energy
    scope = scope.where(rarity: @rarity) if @rarity
    scope = scope.where(regulation_mark: @mark) if @mark
    scope.left_outer_joins(:card_set)
         .order(Arel.sql("card_sets.release_date IS NULL, card_sets.release_date DESC, CAST(cards.set_number AS INTEGER)"))
  end

  def image_content_type(url)
    case File.extname(URI.parse(url).path).downcase
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".webp" then "image/webp"
    when ".gif" then "image/gif"
    else "image/png"
    end
  end
end
