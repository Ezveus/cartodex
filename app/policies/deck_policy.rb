class DeckPolicy < ApplicationPolicy
  # A shared deck shows its decklist and its exports to anybody. Everything else about it —
  # the win/loss record, the tournament PDF (which reads one of the owner's profiles), every
  # write — stays with the owner.
  def show? = owner? || record.shared?
  def export? = show?

  def tournament_pdf? = owner?
  def stats? = owner?
  def results? = owner?

  def update? = owner?
  def edit? = owner?
  def destroy? = owner?
  def duplicate? = owner?
  def share? = owner?

  def index? = user.present?
  def create? = user.present?

  # The index of shared decks is the same page for a visitor and a member.
  def shared_index? = true

  private

  # nil user included: a visitor owns nothing.
  def owner? = user.present? && record.user_id == user.id
end
