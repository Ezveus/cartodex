class TournamentEntryPolicy < ApplicationPolicy
  def show? = owner?
  def create? = owner_or_member?
  def update? = owner?
  def edit? = owner?
  def destroy? = owner?
  def attach_results? = owner?
  def detach_result? = owner?

  private

  # nil user included: a visitor owns nothing.
  def owner? = user.present? && record.user_id == user.id

  # `create?` is asked of a record the controller has just built for current_user, so it is the
  # same question — spelled separately only because a freshly built record's user_id is set
  # from current_user and owner? would be circular to read.
  def owner_or_member? = user.present? && (record.user_id.nil? || record.user_id == user.id)
end
