# The lists a deck was played with: the history, the diff between two neighbours, recording the
# live list as the next version, importing an earlier one, and correcting a date.
#
# Owner only, behind the rule #stats uses — a version is a record of how the deck was played,
# which is the owner's private data. Not PubliclyReachable: its routes leave `authenticate :user`
# by nesting under `resources :decks` alone, ApplicationController's authenticate_user! is its only
# gate, and the lookup is current_user.decks, so a stranger's request is a RecordNotFound — a 404,
# never a 403 that would out the deck's existence. verify_authorized is what catches an action
# that forgets its authorize; PublicAccessTest reaches every read with a session for that reason.
class DeckVersionsController < ApplicationController
  before_action :set_deck
  before_action :set_version, only: %i[show edit update destroy]
  after_action :verify_authorized

  def index
    @versions = @deck.ordered_versions
    @drift = Decks::VersionDrift.call(@deck)

    ids = @versions.map(&:id)
    @result_counts = ids.index_with { DeckResult::RESULTS.index_with(0) }
    DeckResult.where(deck_version_id: ids).group(:deck_version_id, :result).count
      .each { |(version_id, result), count| @result_counts[version_id][result] = count if @result_counts[version_id].key?(result) }
    @entry_counts = TournamentEntry.where(deck_version_id: ids).group(:deck_version_id).count
    @periods = Decks::VersionPeriods.call(@versions)
  end

  def show
    versions = @deck.ordered_versions
    index = versions.index { |version| version.id == @version.id }
    @version = versions[index]
    @previous = index.positive? ? versions[index - 1] : nil

    compared = [ @previous, @version ].compact
    @periods = Decks::VersionPeriods.call(compared)
    ActiveRecord::Associations::Preloader.new(records: compared, associations: { deck_version_cards: :card }).call
    @comparison = Decks::Comparator.call(compared)
  end

  # Defaults to the oldest version's classification: an earlier list was most likely played under
  # the oldest one known, not under whatever the deck carries today. The deck's own when there is
  # no version to go by.
  def new
    source = @deck.deck_versions.first || @deck
    @form = {
      decklist: "", effective_at: "", format: source.format,
      standard_pool_id: source.standard_pool_id.to_s, other_format_name: source.other_format_name.to_s
    }
    @errors = []
    @standard_pools = standard_pools
  end

  def create
    attrs = version_form_params
    result = Decks::VersionImporter.call(
      deck: @deck, decklist: attrs[:decklist], effective_at: attrs[:effective_at], format: attrs[:format],
      standard_pool: StandardPool.find_by(id: attrs[:standard_pool_id]), other_format_name: attrs[:other_format_name]
    )

    if result.version
      redirect_to deck_version_path(@deck, result.version), notice: "Version #{result.version.number} added."
    else
      @form = %i[decklist effective_at format standard_pool_id other_format_name].index_with { |key| attrs[key].to_s }
      @errors = result.errors
      @standard_pools = standard_pools
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @periods = Decks::VersionPeriods.call([ @version ])
  end

  # effective_at only: a version's content is a record of what was played and never changes.
  # Moving the date can renumber the deck's versions, which is the point of allowing it.
  def update
    # Read before the assignment: a refused date would otherwise rank the version where it was
    # refused from going, and the re-rendered form would name the wrong number.
    number = @version.number

    if @version.update(params.expect(deck_version: [ :effective_at ]))
      redirect_to deck_versions_path(@deck), notice: "Version date updated."
    else
      @version.number = number
      @periods = Decks::VersionPeriods.call([ @version ])
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    label = @version.label
    if @version.destroy
      redirect_to deck_versions_path(@deck), notice: "Version #{label} deleted."
    else
      # restrict_with_error's own message names the association, not what a reader needs to know,
      # which is what is in the way and how much of it — the call DecksController#destroy makes.
      redirect_to deck_versions_path(@deck), alert: "#{label} is still recorded on #{blockers}."
    end
  end

  # The explicit "New version": allowed while the live list has moved on from the latest version,
  # or when there is none yet. Without drift it would record a duplicate of the latest.
  def snapshot
    result = Decks::ExplicitSnapshot.call(@deck)

    if result.version
      redirect_to deck_version_path(@deck, result.version), notice: "Version #{result.version.number} recorded."
    else
      redirect_to deck_versions_path(@deck), alert: "The deck still matches #{result.latest.label}: there is nothing new to record."
    end
  end

  private

  def set_deck
    @deck = current_user.decks.find_by!(key: params[:deck_id])
    authorize @deck, :stats?
  end

  def set_version
    @version = @deck.deck_versions.find(params[:id])
  end

  def version_form_params
    params.expect(deck_version: %i[decklist effective_at format standard_pool_id other_format_name])
  end

  def standard_pools
    StandardPool.named.by_release.to_a
  end

  def blockers
    results = @version.deck_results.count
    entries = @version.tournament_entries.count
    [
      (pluralize_count(results, "result") if results.positive?),
      (pluralize_count(entries, "participation") if entries.positive?)
    ].compact.to_sentence
  end

  def pluralize_count(count, word) = "#{count} #{word.pluralize(count)}"
end
