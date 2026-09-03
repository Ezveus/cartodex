# Headless policy — the dashboard has no record. `authorize :dashboard, :show?` routes here.
class DashboardPolicy < ApplicationPolicy
  def show? = true
end
