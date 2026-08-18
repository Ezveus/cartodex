class Collection < ApplicationRecord
  belongs_to :user
  belongs_to :card

  # What a copy physically is, as opposed to which printing it is. Ruby constants
  # rather than database enums: new reverse patterns ship with nearly every set
  # (Prismatic Evolutions alone has three series), so adding one must be a line
  # in a constant, not a migration — while a typo must still be refused.
  #
  # "standard" means the copy as its rarity defines it — non-holo for a Common,
  # holo for a Holo Rare. Named that way rather than "normal", which would
  # wrongly suggest non-holo. There is no "holo" finish: holo is a rarity and
  # already lives on cards.rarity, and a finish repeating it would let two
  # columns contradict each other about the same card.
  LANGUAGES = (%w[unknown] + CardSet::REGION_LANGUAGES.values.flatten).freeze
  FINISHES  = %w[unknown standard reverse_holo poke_ball_reverse master_ball_reverse].freeze

  # Validations
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :finish, inclusion: { in: FINISHES }
  validate :language_allowed_by_set
  validates :user_id, uniqueness: { scope: [ :card_id, :language, :finish ],
                                    message: "already has this printing in this variant" }

  # Scopes
  scope :with_cards, -> { where("quantity > 0") }
  # Held once so the collection page and the MCP tool cannot drift apart on what
  # "filtered by card name" means; see Card.name_matching for the matching rules.
  scope :card_name_matching, ->(query) { joins(:card).merge(Card.name_matching(query)) }

  private

  # The set decides which languages exist for its printings: a Japanese copy
  # cannot hang off a western collector number, because that printing does not
  # exist under that number. When the card has no set — Card belongs_to :card_set
  # is optional — nothing narrows the union.
  def language_allowed_by_set
    return if language == "unknown"

    allowed = card&.card_set&.allowed_languages || LANGUAGES
    errors.add(:language, "is not printed for this set") unless allowed.include?(language)
  end
end
