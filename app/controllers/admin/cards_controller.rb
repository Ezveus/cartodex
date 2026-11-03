module Admin
  class CardsController < BaseController
    before_action :set_card, only: [ :show, :edit, :update, :rescrape ]
    before_action :set_card_set, only: %i[new create]

    def index
      @cards = Card.includes(:card_set).order(:name)
      @cards = @cards.name_matching(params[:q]) if params[:q].present?
      @cards = @cards.limit(50)
    end

    def show; end

    def new
      @card = @card_set.cards.new(set_name: @card_set.code)
      load_slots_from_card
    end

    # The set is the page's, code included: a posted card_set_id or set_name would file the card
    # elsewhere, or under a code its set does not have.
    def create
      @card = @card_set.cards.new(set_full_name: @card_set.name)
      if write(card_params.except(:card_set_id).merge(set_name: @card_set.code))
        redirect_to admin_card_path(@card), notice: "Card created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_slots_from_card
    end

    def update
      old_fingerprint = @card.fingerprint
      if write(card_params)
        redirect_to admin_card_path(@card), notice: update_notice(old_fingerprint)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def rescrape
      url = "https://limitlesstcg.com/cards/#{@card.set_name}/#{@card.set_number}"
      ::Cards::Fetcher.call(url, force: true)
      redirect_to admin_card_path(@card), notice: "Card rescraped."
    rescue => e
      redirect_to admin_card_path(@card), alert: "Rescrape failed: #{e.message}"
    end

    private

    def set_card
      @card = Card.find(params[:id])
    end

    def set_card_set
      @card_set = CardSet.find(params[:card_set_id])
    end

    # Label assignments and archetypes are keyed on fingerprints and their resync tasks walk the
    # whole catalogue, so a moved fingerprint is reported rather than repaired here. While another
    # printing still carries the old fingerprint the resync finds it alive and moves nothing, so
    # naming the tasks there would promise a repair that does not happen.
    def update_notice(old_fingerprint)
      notice = "Card updated."
      return notice unless @card.saved_change_to_fingerprint?

      moved = "#{notice} Its fingerprint moved from #{old_fingerprint} to #{@card.fingerprint}"
      others = Card.where(fingerprint: old_fingerprint).where.not(id: @card.id).count
      if others.positive?
        "#{moved}; #{others} other printing(s) keep #{old_fingerprint}, so its labels and archetypes stay with them."
      else
        "#{moved}: run bin/rails card_labels:resync_fingerprints and bin/rails archetypes:resync_fingerprints."
      end
    end

    # On a refusal the form re-renders what was typed, so the slots stay as submitted.
    def write(attributes)
      @attacks = slot_params(:attacks, ::Cards::ManualWriter::ATTACK_FIELDS)
      @abilities = slot_params(:abilities, ::Cards::ManualWriter::ABILITY_FIELDS)
      ::Cards::ManualWriter.call(@card, attributes: attributes.to_h, attacks: @attacks, abilities: @abilities)
    end

    def load_slots_from_card
      @attacks = @card.attacks.map { _1.attributes.slice(*::Cards::ManualWriter::ATTACK_FIELDS) }
      @abilities = @card.abilities.map { _1.attributes.slice(*::Cards::ManualWriter::ABILITY_FIELDS) }
    end

    def card_params
      params.require(:card).except(:attacks, :abilities).permit(
        :name, :card_type, :stage, :subtype, :evolves_from, :hp, :type_symbol, :weakness, :resistance,
        :retreat_cost, :rarity, :regulation_mark, :set_name, :set_number, :card_set_id, :artist,
        :image_url, :effect
      )
    end

    # The form posts slots as a Hash keyed "0", "1", …; the integer order is the slot order, which
    # a String sort would break past slot 9.
    def slot_params(key, fields)
      slots = params.require(:card)[key]
      return [] unless slots.is_a?(ActionController::Parameters)

      slots.keys.select { _1.match?(/\A\d+\z/) }.sort_by(&:to_i).filter_map do |index|
        slot = slots[index]
        slot.permit(*fields).to_h.to_hash if slot.is_a?(ActionController::Parameters)
      end
    end
  end
end
