class TournamentEntryPolicy < ApplicationPolicy
  def show? = owner?
  def create? = owner?
  def update? = owner?
  def edit? = owner?
  def destroy? = owner?
  def attach_results? = owner?
  def detach_result? = owner?

  private

  # nil user included: a visitor owns nothing.
  def owner? = user.present? && record.user_id == user.id
end
