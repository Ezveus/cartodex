module Api
  class ArchetypesController < ApplicationController
    before_action :authenticate_user!

    def index
      q = params[:q].to_s.strip
      archetypes = if q.present?
        Archetype.search(q).includes(:primary_card, :secondary_card).limit(10)
      else
        Archetype.includes(:primary_card, :secondary_card).order(:name).limit(10)
      end

      render json: archetypes.map { |a| archetype_json(a) }
    end

    def create
      primary = Card.find(params[:primary_card_id])
      secondary = params[:secondary_card_id].present? ? Card.find(params[:secondary_card_id]) : nil

      archetype = existing(primary, secondary) || build(primary, secondary)
      archetype.save! if archetype.new_record?

      render json: archetype_json(archetype), status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Card not found" }, status: :not_found
    # A concurrent create caught by the model's uniqueness *validation*: it runs
    # its own SELECT, so a winner that commits between our `existing` lookup and
    # that SELECT is refused here rather than by the index. The wider of the two
    # race windows, and the likelier one — a double-click on "Create & select"
    # sends two POSTs. Any other validation error is a genuine 422.
    rescue ActiveRecord::RecordInvalid => e
      if e.record.errors.of_kind?(:primary_fingerprint, :taken)
        render_race_winner(primary, secondary, e.record.errors.full_messages)
      else
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end
    # The narrower window: validation passed, and the winner committed before our
    # INSERT reached the unique index.
    rescue ActiveRecord::RecordNotUnique
      render_race_winner(primary, secondary, [ "Archetype already exists" ])
    end

    private

    # The loser of a create race wants exactly what the winner just created —
    # this endpoint is idempotent on the fingerprint pair — so re-read rather
    # than report a failure the user cannot act on. `errors` is the fallback for
    # the case where the re-read finds nothing, which means the refusal was not
    # the race it looked like.
    def render_race_winner(primary, secondary, errors)
      archetype = existing(primary, secondary)

      if archetype
        render json: archetype_json(archetype), status: :created
      else
        render json: { errors: errors }, status: :unprocessable_entity
      end
    end

    # Identity is the fingerprint pair, not the pair of card ids: designating a
    # different printing of the same card is the same archetype. Looking up by id
    # would miss it, go to save!, and be refused by the unique index — a 500 for
    # what the user experiences as a no-op.
    #
    # A card with no fingerprint has no place in that key, and that is true of the
    # secondary too: `""` means "no secondary", so a *present* secondary that
    # resolves to `""` would match a single-member archetype on the same primary
    # and quietly drop the card the user chose. Both halves fall through to `build`,
    # where the model's presence validations answer with a readable 422.
    def existing(primary, secondary)
      return nil if primary.fingerprint.blank?
      return nil if secondary && secondary.fingerprint.blank?

      Archetype.find_by(
        primary_fingerprint: primary.fingerprint,
        secondary_fingerprint: secondary&.fingerprint.to_s
      )
    end

    def build(primary, secondary)
      Archetype.new(primary_card: primary, secondary_card: secondary, parent_id: params[:parent_id])
    end

    def archetype_json(a)
      {
        id: a.id,
        name: a.name,
        primary_card: card_json(a.primary_card),
        secondary_card: card_json(a.secondary_card),
        parent_id: a.parent_id
      }
    end

    # The printing, not a bare name: several cards share a name, and which one an
    # archetype designates is now the user's choice to make and to see.
    def card_json(card)
      return nil if card.nil?

      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number }
    end
  end
end
