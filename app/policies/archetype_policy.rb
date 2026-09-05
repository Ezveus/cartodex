class ArchetypePolicy < ApplicationPolicy
  # `user.present?` and not `true`, today. Both pages are declared inside routes.rb's
  # `authenticate :user` block, so a nil user never reaches either action and no request can tell
  # the two answers apart — which is exactly why the policy has to say which one it means. The
  # rule today is "members only", and flipping these two to `true` is the third of the three
  # gestures that open the pages to visitors (see the comment atop ArchetypesController). Written
  # out one by one rather than aliased, so that flip stays a two-line edit with nothing implied.
  #
  # A nil user is allowed to reach here rather than raise, per ApplicationPolicy: every public
  # page in this app instantiates a policy with one.
  def index? = user.present?
  def show? = user.present?
end
