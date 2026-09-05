# The label vocabulary: what a card *is* beyond its card_type ("type"), and — from stage 2 — what
# it *does* ("role").
#
# The two families are governed differently on purpose. A `role` slug is referenced by code, since
# stage 2's suggestion rules are keyed on it, so an admin-invented role would be a label no rule
# can ever propose; a `type` slug is referenced by nothing but its own `source_query`, so a new one
# is a row plus a run. Admin::CardLabelsController is where that asymmetry is enforced.
class CardLabel < ApplicationRecord
  FAMILIES = %w[role type].freeze

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

  scope :roles, -> { where(family: "role").order(:position, :slug) }
  scope :types, -> { where(family: "type").order(:position, :slug) }

  def role? = family == "role"
  def type? = family == "type"

  # Only a label that says where to read it can be imported. The admin screen offers the action on
  # exactly these.
  def importable? = source_query.present?
end
