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
    if @profile.destroy
      redirect_to tournament_profiles_path, notice: "Tournament profile deleted."
    else
      # restrict_with_error's own message names the association, not what a reader needs to
      # know, which is whose data is in the way and how much of it — same shape as
      # TournamentsController#destroy.
      count = @profile.tournament_entries.count
      redirect_to tournament_profiles_path,
        alert: "This profile still has #{count} #{"participation".pluralize(count)} recorded against it."
    end
  end

  private

  def set_profile
    @profile = current_user.tournament_profiles.find(params[:id])
  end

  def profile_params
    params.require(:tournament_profile).permit(:player_name, :player_id, :date_of_birth)
  end
end
