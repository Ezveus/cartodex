# Base policy. Written by hand rather than generated, for one reason: Pundit's generator
# template has been known to `raise` on a nil user, and in this app `current_user` is nil on
# every public page. A policy that rejects an absent user makes the whole public surface
# impossible, so `user` is simply allowed to be nil and each query says what it means.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class} must implement #resolve"
    end
  end
end
