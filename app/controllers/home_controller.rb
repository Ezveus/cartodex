class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :welcome ]

  def welcome
    redirect_to dashboard_path if user_signed_in?
  end

  def dashboard
    authenticate_user!
  end
end
