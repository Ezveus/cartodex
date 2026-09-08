class DeckPolicy < ApplicationPolicy
  # A shared deck shows its decklist and its exports to anybody. Everything else about it —
  # the win/loss record, the tournament PDF (which reads one of the owner's profiles), every
  # write — stays with the owner.
  def show? = owner? || record.shared?
  def export? = show?

  # `shared?` alone, deliberately not `show?`, even though the two agree for every reader who is
  # not the owner. The image is fetched by a crawler that has no session, so an owner-only yes buys
  # nothing — and it costs something: on the owner's own private deck page it would emit an
  # og:image every crawler is then refused, which renders worse than the generic banner it
  # replaced. `og_image? = show?` is green on every test that requests the endpoint as a stranger,
  # so the test that discriminates the two is the owner asking for their *own* private deck's
  # image and being refused.
  def og_image? = record.shared?

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
