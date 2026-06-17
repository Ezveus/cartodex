class CardsController < ApplicationController
  include CardSearchable

  PER_PAGE = 48

  def index
    @blocks = CardSet.by_release
                     .includes(:cards)
                     .group_by(&:block_name)
    @current_set = CardSet.find_by(code: params[:set]) if params[:set].present?

    @query  = params[:q].to_s.strip
    @type   = params[:type].presence
    @energy = params[:energy].presence
    @rarity = params[:rarity].presence
    @mark   = params[:mark].presence
    @page   = [ params[:page].to_i, 1 ].max

    @searching = @query.length >= 2 || @type || @energy || @rarity || @mark

    @rarities = Card.where.not(rarity: [ nil, "" ]).distinct.order(:rarity).pluck(:rarity)
    @marks    = Card.where.not(regulation_mark: [ nil, "" ]).distinct.order(:regulation_mark).pluck(:regulation_mark)

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
    @alt_printings = Card.where(name: @card.name, fingerprint: @card.fingerprint)
                         .where.not(id: @card.id)
                         .order(:set_name)
    @collection_quantity = current_user.collections.find_by(card_id: @card.id)&.quantity.to_i
  end

  def image
    card = Card.find(params[:id])
    return head :not_found if card.image_url.blank?

    begin
      body = HttpFetcher.call(card.image_url)
    rescue HttpFetcher::FetchError => e
      Rails.logger.warn "Image proxy failed for card #{card.id}: #{e.message}"
      return head :bad_gateway
    end

    expires_in 30.days, public: false
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
