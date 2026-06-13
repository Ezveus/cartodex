class CardsController < ApplicationController
  RESULT_LIMIT = 200

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

    @searching = @query.length >= 2 || @type || @energy || @rarity || @mark

    @rarities = Card.where.not(rarity: [ nil, "" ]).distinct.order(:rarity).pluck(:rarity)
    @marks    = Card.where.not(regulation_mark: [ nil, "" ]).distinct.order(:regulation_mark).pluck(:regulation_mark)

    if @searching
      scope = filtered_scope
      @total = scope.count
      @cards = scope.limit(RESULT_LIMIT)
    elsif @current_set
      @cards = @current_set.cards.order(Arel.sql("CAST(set_number AS INTEGER)"))
    else
      @cards = Card.none
    end
  end

  def show
    @card = Card.includes(:attacks, :abilities, :pokemon_subtype).find(params[:id])
    @alt_printings = Card.where(name: @card.name, fingerprint: @card.fingerprint)
                         .where.not(id: @card.id)
                         .order(:set_name)
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
    scope = apply_name_filter(scope, @query) if @query.length >= 2
    scope = scope.where(card_type: @type) if @type
    scope = scope.where(type_symbol: @energy) if @energy
    scope = scope.where(rarity: @rarity) if @rarity
    scope = scope.where(regulation_mark: @mark) if @mark
    scope.left_outer_joins(:card_set)
         .order(Arel.sql("card_sets.release_date IS NULL, card_sets.release_date DESC, CAST(cards.set_number AS INTEGER)"))
  end

  # Parses "name [SET_CODE] [NUMBER]" like Api::CardsController, so a query such as
  # "Pikachu SVI 25" narrows by name, set and number at once.
  def apply_name_filter(scope, query)
    tokens = query.split(/\s+/)
    number = tokens.pop if tokens.length > 1 && tokens.last.match?(/\A\d+\z/)
    code   = tokens.pop if tokens.length > 1 && set_code?(tokens.last)
    name   = tokens.join(" ")

    scope = scope.where("cards.name LIKE ?", "%#{name}%") if name.present?
    scope = scope.where("UPPER(cards.set_name) = ?", code.upcase) if code
    scope = scope.where(set_number: number) if number
    scope
  end

  def set_code?(token)
    token.match?(/\A[a-zA-Z]{2,5}\z/) &&
      CardSet.where("UPPER(code) = ?", token.upcase).exists?
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
