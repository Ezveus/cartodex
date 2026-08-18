class CardSet < ApplicationRecord
  has_many :cards, dependent: :nullify

  # The print run a set belongs to decides which languages its printings exist
  # in. The region is the fact; the languages are derived, so there is no per-set
  # column to maintain. The western six share the international numbering — a
  # French Base Set card really is 10/102 — while every other region has its own
  # set releases, so hanging `ja` off a western collector number would assert a
  # printing that does not exist.
  REGION_LANGUAGES = {
    "international" => %w[en fr de es it pt],
    "japan"         => %w[ja],
    "korea"         => %w[ko],
    "taiwan"        => %w[zh-Hant],
    "china"         => %w[zh-Hans],
    "thailand"      => %w[th],
    "indonesia"     => %w[id]
  }.freeze

  validates :code, presence: true, uniqueness: { scope: :region }
  validates :name, presence: true
  validates :region, inclusion: { in: REGION_LANGUAGES.keys }

  scope :by_release, -> { order(release_date: :desc) }

  def allowed_languages = REGION_LANGUAGES.fetch(region)
end
