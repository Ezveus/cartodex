# Recomputes the denormalised fingerprint columns on `archetypes` from the cards
# they point at, and reports the pairs that collide once refreshed.
#
# Those columns exist only to back the unique index — detection reads
# `cards.fingerprint` through a join, never this copy — so drift is tolerable and
# this is a repair tool, not a callback on Card. A `force: true` rescrape that
# corrects an attack moves that card's fingerprint; a Card callback would then
# have to fail a whole set rescrape halfway through to keep the index honest.
# Running this afterwards brings the columns back in step instead, and names any
# duplicate the drift has let through rather than picking one to overwrite.
class Archetypes::FingerprintSync < ApplicationService
  Result = Struct.new(:updated, :collisions, keyword_init: true)

  def call
    desired = Archetype.includes(:primary_card, :secondary_card).map { |archetype|
      [ archetype, archetype.primary_card&.fingerprint, archetype.secondary_card&.fingerprint.to_s ]
    }

    collisions = colliding(desired)
    updated = desired.reject { |(archetype, _, _)| collisions.include?(archetype) }
      .count { |(archetype, primary, secondary)| write(archetype, primary, secondary) }

    Result.new(updated: updated, collisions: collisions)
  end

  private

  # Archetypes whose *refreshed* pair would not be unique. Grouped on the target
  # values rather than the stored ones: the whole point is to catch a collision
  # before writing it, since the index would only raise on the second write and
  # leave the first one applied.
  def colliding(desired)
    duplicated = desired.group_by { |(_, primary, secondary)| [ primary, secondary ] }
      .select { |_, rows| rows.size > 1 }
      .keys

    desired.select { |(_, primary, secondary)| duplicated.include?([ primary, secondary ]) }
      .map(&:first)
  end

  # update_columns skips validations and callbacks on purpose: the values are
  # already derived from the live cards, and re-running auto_generate_name here
  # would rename archetypes as a side effect of a repair.
  #
  # Known limitation: two archetypes swapping pairs can still raise
  # ActiveRecord::RecordNotUnique here, because the first write transiently
  # collides with the other's not-yet-updated row. Re-running resolves it, and a
  # raise is the right failure mode — loud, and nothing was lost.
  def write(archetype, primary, secondary)
    return false if [ archetype.primary_fingerprint, archetype.secondary_fingerprint ] == [ primary, secondary ]

    archetype.update_columns(primary_fingerprint: primary, secondary_fingerprint: secondary)
    true
  end
end
