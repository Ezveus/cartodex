# The card catalog is public. A policy that says "yes, to everyone" is not ceremony here: it
# is the written trace of that decision, and it is what stops verify_authorized from having a
# blind spot over the cards controller.
class CardPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def image? = true
end
