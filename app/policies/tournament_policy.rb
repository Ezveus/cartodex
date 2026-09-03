class TournamentPolicy < ApplicationPolicy
  # The catalog and an event's page are public. Written down rather than left true by
  # omission, so that verify_authorized has no blind spot over this controller.
  def index? = true
  def show? = true

  def mine? = user.present?
  def create? = user.present?

  def update? = creator_or_admin?
  def edit? = creator_or_admin?
  def destroy? = creator_or_admin?

  private

  # This is the one policy in the app that reads admin?, and it is not the rule CLAUDE.md's
  # deck paragraph protects. Nothing about an event is hidden — it is listed at /tournaments —
  # so an admin correcting a catalog entry gains no read they did not already have. The
  # alternative was an Admin::TournamentsController duplicating three actions to say the same
  # thing. A participation is different, and TournamentEntryPolicy grants an admin nothing.
  def creator_or_admin? = user.present? && (record.created_by_id == user.id || user.admin?)
end
