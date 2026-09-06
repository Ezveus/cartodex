# The label vocabulary: what a card *is* beyond its card_type ("type"), and — from stage 2 — what
# it *does* ("role").
#
# The two families are governed differently on purpose. A `role` slug is referenced by code, since
# stage 2's suggestion rules are keyed on it, so an admin-invented role would be a label no rule
# can ever propose; a `type` slug is referenced by nothing but its own `source_query`, so a new one
# is a row plus a run. Admin::CardLabelsController is where that asymmetry is enforced.
class CardLabel < ApplicationRecord
  FAMILIES = %w[role type].freeze

  # The `role` vocabulary, and the reason this family is a constant while `type` is data: every
  # slug here is read by a rule in CardLabels::RoleSuggester, so a role invented in the admin panel
  # would be a label no rule can ever propose, and a role deleted there would be a rule proposing
  # a label that no longer exists. db/seeds/card_labels.rb walks this list; Admin::CardLabelsController
  # refuses `create` and `destroy` on the family, and permits neither `family` on update.
  #
  # The slugs are kebab-case because the validation below refuses anything else — `energy_acceleration`
  # reads better in Ruby and would fail at seed time on a fresh database, where nothing but a
  # missing role row would report it.
  #
  # Roles are game mechanics and a property of the *card*, never of the archetype playing it:
  # Fezandipiti ex is `draw` in a deck that attacks with it, and a Basic whose attack fetches two
  # Basics is `search`. "Attacker" is deliberately absent — every Pokémon is a potential attacker,
  # so it says nothing.
  ROLES = [
    { slug: "draw", name: "Draw", position: 10,
      description: "Puts cards from the deck into the hand without naming what it takes." },
    { slug: "search", name: "Search", position: 20,
      description: "Searches the deck for named cards and puts them into the hand or into play." },
    { slug: "gust", name: "Gust", position: 30,
      description: "Brings one of the opponent's Benched Pokémon to the Active Spot." },
    { slug: "switch", name: "Switch", position: 40,
      description: "Moves your own Active Pokémon out of the Active Spot." },
    { slug: "recovery", name: "Recovery", position: 50,
      description: "Returns cards from the discard pile to the hand or the deck." },
    { slug: "disruption", name: "Disruption", position: 60,
      description: "Acts on the opponent's hand, deck or board rather than on your own." },
    { slug: "energy-acceleration", name: "Energy acceleration", position: 70,
      description: "Attaches Energy from somewhere other than the turn's own attachment." }
  ].freeze

  has_many :assignments, class_name: "CardLabelAssignment", dependent: :destroy

  # Lowercase kebab, because the slug reaches a URL query and a DOM class, and stage 2's rules key
  # on it.
  validates :slug, presence: true, uniqueness: true, format: {
    with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
    message: "must be lowercase words joined by dashes"
  }
  validates :name, presence: true
  validates :family, inclusion: { in: FAMILIES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # Blank is allowed: a `role` label has no search token at all, and a curated `type` label need
  # not either (see `importable?`). Reuses CardLabels::LimitlessSearch::TOKEN_RE rather than
  # respelling the pattern, so the two never drift apart — without this, a typo'd token was only
  # ever caught inside CardLabels::ImportJob, after the admin had already been told to watch the
  # imports table for a result that was never going to come.
  validates :source_query, format: {
    with: CardLabels::LimitlessSearch::TOKEN_RE, message: "is not a valid Limitless search token"
  }, allow_blank: true

  scope :roles, -> { where(family: "role").order(:position, :slug) }
  scope :types, -> { where(family: "type").order(:position, :slug) }

  def role? = family == "role"
  def type? = family == "type"

  # Only a label that says where to read it can be imported. The admin screen offers the action on
  # exactly these.
  def importable? = source_query.present?
end
