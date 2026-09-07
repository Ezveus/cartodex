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
    # `free-retreat` and `retreat-tax` are two roles and not one, because they are opposites: 41
    # catalogue fingerprints mention a retreat cost and they carry both senses — Air Balloon and
    # Latias ex make retreating cheaper while Gravity Gemstone and Mega Chandelure ex make it
    # dearer. A single "retreat cost" role would render as a section that looks complete with a
    # quarter of it backwards.
    #
    # Their positions are 45 and 65 rather than the next two multiples of ten, and that *is* the
    # answer to "these get used the way Switch does": the model has no notion of two roles being
    # adjacent — a card carries several, roles do not relate to each other — and inventing one
    # would be a new concept. `position` already orders the report's sections, so 45 seats Free
    # retreat beside `switch` (40) and 65 seats Retreat tax beside `disruption` (60), each next to
    # the role a reader compares it against, and both fill gaps that renumber nothing.
    #
    # "Free retreat" over-claims for Air Balloon, which is −2 rather than free. Taken knowingly:
    # `gust`'s precedent is that a player's own word wins where one exists, and the literal pair
    # (`retreat-reduction` / `retreat-increase`) is duller in a heading. **The description does not
    # make up for it where a reader would meet the name**: it reaches the curation screen's
    # checkbox `title` and the `type` family's badge, and a role never renders as a badge — the
    # report's section heading is the name alone. So the over-claim is visible on
    # `/archetypes/:id` and the nuance is not, which is the price of the idiom rather than a
    # mitigation of it.
    #
    # A second gap, and it is a vocabulary question rather than curation debt: the description says
    # nothing about *whose* Pokémon. `retreat-tax`'s hedges ("usually the opponent's") and this one
    # cannot, because 3 of its 23 matches — N's Castle, Beach Court, Paradise Resort, and N's
    # Castle is played — grant free retreat to both players. A curator asked whether N's Castle is
    # `free-retreat` has no right answer.
    #
    # **This list is declared in `position` order, and that is load-bearing rather than tidy**:
    # `CardLabel.roles` is `order(:position, :slug)`, and CardLabelSeedTest asserts the seeded rows
    # come back in the order this array declares them. Appending a role with an interleaving
    # position turns that test red — which is how these two were found to belong in their slots.
    { slug: "free-retreat", name: "Free retreat", position: 45,
      description: "Removes or reduces the Energy a Pokémon must discard to retreat." },
    { slug: "recovery", name: "Recovery", position: 50,
      description: "Returns cards from the discard pile to the hand or the deck." },
    { slug: "disruption", name: "Disruption", position: 60,
      description: "Acts on the opponent's hand, deck or board rather than on your own." },
    { slug: "retreat-tax", name: "Retreat tax", position: 65,
      description: "Raises a Retreat Cost, usually the opponent's, to hold a Pokémon in play." },
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
