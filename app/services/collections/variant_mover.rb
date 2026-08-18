module Collections
  # Moves copies of one printing from one variant to another: the "one of these
  # four is French" split, and its undo. The owned total is unchanged by
  # construction, which is why this is one service rather than a QuantitySetter
  # followed by a CardAdder — those two writes would dip the total between them,
  # and since Σ owned_copies(card) ≤ owned(card) is surfaced rather than
  # enforced, a concurrent reader would see an over-allocation that never
  # existed.
  class VariantMover < ApplicationService
    # After the transaction nothing in the database says whether the target
    # pre-existed or was just created, nor that the source is gone. Both facts
    # are decided inside it, so they are carried out — the same reason
    # Decks::PrintingSwapper returns a Result.
    Result = Struct.new(:source, :target, :merged, :source_removed, keyword_init: true)

    def initialize(user:, card:, from_language:, from_finish:, to_language:, to_finish:, quantity:)
      @user = user
      @card = card
      @from_language = from_language
      @from_finish = from_finish
      @to_language = to_language
      @to_finish = to_finish
      @quantity = quantity
    end

    def call
      raise ArgumentError, "quantity must be a positive integer" unless @quantity.is_a?(Integer) && @quantity.positive?
      raise ArgumentError, "source and target variants must differ" if same_variant?

      serialized_transaction do
        source = @user.collections.find_by!(card: @card, language: @from_language, finish: @from_finish)
        raise ArgumentError, "source variant holds only #{source.quantity} copies" if source.quantity < @quantity

        target = @user.collections.find_or_initialize_by(card: @card, language: @to_language, finish: @to_finish)
        merged = target.persisted?
        target.quantity = target.quantity.to_i + @quantity
        target.save!

        source_removed = source.quantity == @quantity
        source_removed ? source.destroy! : source.update!(quantity: source.quantity - @quantity)

        Result.new(source: source, target: target, merged: merged, source_removed: source_removed)
      end
    end

    private

    def same_variant?
      [ @from_language, @from_finish ] == [ @to_language, @to_finish ]
    end
  end
end
