# Wiki governance: any signed-in member may add, correct or delete any row of an event's
# standings sheet, because the sheet is the event's public record and not anybody's property.
#
# This policy grants an admin nothing beyond a member, unlike TournamentPolicy: there is no
# moderation question here that a member cannot already answer, since every member can already
# edit every row. And the one thing that *is* somebody's own — their participation — is guarded
# by #unclaim below, exactly as TournamentEntryPolicy guards an entry.
class TournamentStandingPolicy < ApplicationPolicy
  def create? = user.present?
  def new? = create?
  def update? = user.present?
  def edit? = update?
  def destroy? = user.present?

  # Which entry may be claimed is enforced by the controller's scoped lookup
  # (current_user.tournament_entries), not here: the policy is handed the standing, and the entry
  # arrives as a parameter it never sees.
  def claim? = user.present?

  # The one owner-scoped rule. Anybody may correct the public data on a row; only the member whose
  # participation is linked may sever the link — and an unlinked row can be unclaimed by nobody.
  def unclaim? = user.present? && record.tournament_entry&.user_id == user.id
end
