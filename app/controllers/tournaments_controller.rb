class TournamentsController < ApplicationController
  include Searchable

  before_action :set_tournament, only: %i[show edit update destroy]
  before_action :set_form_collections, only: %i[new create edit update]

  def index
    @query = search_query
    @tournaments = current_user.tournaments.includes(:deck, :tournament_profile).order(date: :desc)
    @tournaments = @tournaments.name_matching(@query) if @query.present?
  end

  def show
    @unassigned_results = @tournament.deck.deck_results.where(tournament_id: nil).order(played_at: :desc)
  end

  def new
    @tournament = current_user.tournaments.build(date: Date.current)
  end

  def create
    @tournament = current_user.tournaments.build(tournament_params)

    if @tournament.save
      redirect_to @tournament, notice: "Tournament created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @tournament.update(tournament_params)
      redirect_to @tournament, notice: "Tournament updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tournament.destroy
    redirect_to tournaments_path, notice: "Tournament deleted."
  end

  private

  def set_tournament
    @tournament = current_user.tournaments
      .includes(:deck, :tournament_profile, deck_results: :archetype)
      .find(params[:id])
  end

  def set_form_collections
    @decks = current_user.decks.order(:name)
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
  end

  def tournament_params
    params.require(:tournament).permit(
      :name, :date, :format, :other_format_name, :tier, :deck_id, :tournament_profile_id,
      :participant_count, :placement, :championship_points
    )
  end
end
