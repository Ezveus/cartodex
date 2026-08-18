class CardSet < ApplicationRecord
  has_many :cards, dependent: :nullify

  # The print run a set belongs to decides which languages its printings exist
  # in. The region is the fact; the languages are derived, so there is no per-set
  # column to maintain. The western six share the international numbering — a
  # French Base Set card really is 10/102 — while every other region has its own
  # set releases, so hanging `ja` off a western collector number would assert a
  # printing that does not exist.
  REGION_LANGUAGES = {
    "international" => %w[en fr de es it pt].freeze,
    "japan"         => %w[ja].freeze,
    "korea"         => %w[ko].freeze,
    "taiwan"        => %w[zh-Hant].freeze,
    "china"         => %w[zh-Hans].freeze,
    "thailand"      => %w[th].freeze,
    "indonesia"     => %w[id].freeze
  }.freeze

  validates :code, presence: true, uniqueness: { scope: :region }
  validates :name, presence: true
  validates :region, inclusion: { in: REGION_LANGUAGES.keys }

  scope :by_release, -> { order(release_date: :desc) }

  # Deliberately strict: `region` is constrained by a validation, so a value that
  # is not a key can only come from raw SQL or update_column, and that is a bug
  # worth surfacing rather than papering over with a default nobody asked for.
  def allowed_languages = REGION_LANGUAGES.fetch(region)
end
