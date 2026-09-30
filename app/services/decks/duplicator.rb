# Copies a deck into `user`'s decks: the owner duplicating their own, or a member taking somebody
# else's shared deck (a field list included) to play and edit as theirs.
#
# The two cases copy different things on purpose. A member's own copy sits beside its source, so
# it is prefixed and keeps everything about how they play it. A copy of somebody else's deck takes
# what the list *is* — name, format, archetype, printings — and leaves the author's description and
# play flags (`physical`, `tcg_live`) behind. Either way the copy is private (`shared` is never
# copied) and carries no versions, results or entries.
class Decks::Duplicator < ApplicationService
  NAME_PREFIX = "Copy of "

  def initialize(deck, user:)
    @deck = deck
    @user = user
  end

  def call
    ActiveRecord::Base.transaction do
      new_deck = @user.decks.create!(own? ? own_attributes : reader_attributes)

      # owned_copies deliberately stays at 0: the real cards are still committed to the source
      # deck, so the copy starts out fully proxied and the user allocates it themselves.
      @deck.deck_cards.find_each do |dc|
        new_deck.deck_cards.create!(card_id: dc.card_id, quantity: dc.quantity)
      end

      new_deck
    end
  end

  private

  # `@deck.user_id` is nil for a field list, and a nil user is refused before this is reached.
  def own? = @deck.user_id == @user.id

  def own_attributes
    list_attributes.merge(
      name: "#{NAME_PREFIX}#{@deck.name}",
      description: @deck.description,
      physical: @deck.physical,
      tcg_live: @deck.tcg_live
    )
  end

  def reader_attributes
    list_attributes.merge(name: @deck.name)
  end

  # The pool travels with the format: a TEF-CRI list copied today is still a TEF-CRI list.
  def list_attributes
    {
      format: @deck.format,
      other_format_name: @deck.other_format_name,
      standard_pool_id: @deck.standard_pool_id,
      archetype_id: archetype_id
    }
  end

  # A field list's archetype is its standing's, not its own column: the column is
  # Decks::ArchetypeDetector's guess at import and contradicts the standing on 512 of 1798 field
  # lists in development (see Archetypes::DeckList). The column is the fallback for a deck no
  # standing names, which is what a member's deck is.
  #
  # index_tournament_standings_on_deck_id is not unique, so the oldest standing decides: it is the
  # one whose import created the list.
  def archetype_id
    standing_archetype_id = TournamentStanding.where(deck_id: @deck.id).order(:id).pick(:archetype_id)
    standing_archetype_id || @deck.archetype_id
  end
end
