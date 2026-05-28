class CardsController < ApplicationController
  def index
    @blocks = CardSet.by_release
                     .includes(:cards)
                     .group_by(&:block_name)
    @current_set = if params[:set].present?
      CardSet.find_by(code: params[:set])
    end
    @cards = @current_set ? @current_set.cards.order(Arel.sql("CAST(set_number AS INTEGER)")) : Card.none
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

  def image_content_type(url)
    case File.extname(URI.parse(url).path).downcase
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".webp" then "image/webp"
    when ".gif" then "image/gif"
    else "image/png"
    end
  end
end
