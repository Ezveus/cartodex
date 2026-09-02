class HomeController < ApplicationController
  include PubliclyReachable

  # #welcome and its route are removed in Task 11; kept public here alongside #dashboard.
  publicly_reachable :welcome, :dashboard

  def welcome
    authorize :dashboard, :show?
    redirect_to dashboard_path if user_signed_in?
  end

  def dashboard
    authorize :dashboard, :show?
    @pending_deck_imports = current_user ? current_user.imports.deck_imports.pending : []
  end
end
