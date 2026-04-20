class TournamentProfilesController < ApplicationController
  before_action :set_profile, only: %i[edit update destroy]

  def index
    @profiles = current_user.tournament_profiles.order(:player_name)
  end

  def new
    @profile = current_user.tournament_profiles.build
  end

  def create
    @profile = current_user.tournament_profiles.build(profile_params)

    if @profile.save
      redirect_to tournament_profiles_path, notice: "Tournament profile created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @profile.update(profile_params)
      redirect_to tournament_profiles_path, notice: "Tournament profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @profile.destroy
    redirect_to tournament_profiles_path, notice: "Tournament profile deleted."
  end

  private

  def set_profile
    @profile = current_user.tournament_profiles.find(params[:id])
  end

  def profile_params
    params.require(:tournament_profile).permit(:player_name, :player_id, :date_of_birth)
  end
end
