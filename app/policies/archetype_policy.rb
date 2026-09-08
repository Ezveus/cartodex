class ArchetypePolicy < ApplicationPolicy
  # `true`, unconditionally, and written out one by one rather than aliased — the shape
  # CardPolicy, DashboardPolicy and TournamentPolicy's two reads have, and for the same reason:
  # "the archetype catalog and one archetype's report are public" is a decision, and a policy
  # that said it by omission would leave `verify_authorized` a blind spot over this controller.
  #
  # A nil user reaches here rather than raising, per ApplicationPolicy: every public page in this
  # app instantiates a policy with one. Nothing here reads `admin?` — an archetype is public
  # factual data with no owner, so being an admin buys nothing, which ArchetypePolicyTest pins.
  def index? = true
  def show? = true
  def og_image? = true
end
