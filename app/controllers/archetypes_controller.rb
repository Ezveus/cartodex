# The archetype catalog and one archetype's metagame report. Everything here reads; nothing
# writes.
#
# Member-only for now. Opening the two pages to visitors is exactly three gestures:
#
#   1. move `resources :archetypes` out of the `authenticate :user` block in config/routes.rb,
#   2. `include PubliclyReachable` here, with `publicly_reachable :index, :show`,
#   3. flip ArchetypePolicy#index?/#show? from `user.present?` to `true`.
#
# A fourth belongs to that day and not to this one: a per-IP
# `rate_limit … unless: -> { user_signed_in? }` sized like tournaments#index's 60/min, since
# #index is the same shape and the same cost — a field debounced at 300ms driving a paginated
# listing behind a Turbo Frame. It is deliberately *not* added now. No anonymous request can
# reach the route while the resource sits inside the authenticate block, so nothing can exercise
# the limiter: not a test, not a bot, not a mistake. A limiter nobody can exercise is a limiter
# nobody knows works, and shipping one now would only make step 4 look already done.
class ArchetypesController < ApplicationController
  include Searchable

  after_action :verify_authorized

  PER_PAGE = 24

  def index
    authorize Archetype, :index?
    @query = search_query

    scope = Archetype.all
    scope = scope.search(@query) if @query.present?

    # Counted on the ungrouped relation on purpose: the ordering query below carries a GROUP BY,
    # and `count` on a grouped relation answers with a Hash of per-group counts rather than a
    # number.
    @pages = (scope.count / PER_PAGE.to_f).ceil
    # Clamped for the reason tournaments#index is: `?page=99` otherwise renders "No archetypes
    # yet." over a catalog that is not empty.
    @page = requested_page.clamp(1, [ @pages, 1 ].max)

    @archetypes = page_of(scope)
    @counts = Archetypes::IndexCounts.call(archetype_ids: @archetypes.map(&:id))
  end

  def show
    # Preloaded because Archetypes::Identity reads all four: both member cards (their art, name
    # and printing_label), the parent this is a variant of, and the variants of it. Left lazy
    # that is four more queries on a page whose whole point is that its cost does not move with
    # the data.
    @archetype = Archetype.preload(:primary_card, :secondary_card, :parent, :children)
                          .find(params[:id])
    authorize @archetype

    # The id, not a slug: archetype names contain "/" (Froslass / Munkidori), and unlike a deck
    # there is nothing here worth keeping unenumerable.
    @scope = Archetypes::MetagameScope.call(archetype: @archetype, pool_param: params[:pool])
    # Two different populations, from the one service that decides them: the card report can only
    # speak for the standings whose decklist somebody typed, while a recorded placement is a
    # result whether or not anybody did.
    @stats = Archetypes::CardStats.call(standings: @scope.listed_standings)
    @performance = Archetypes::Performance.call(standings: @scope.standings)
  end

  private

  # Recorded standings descending, then name. Archetypes nobody has recorded a result for stay
  # listed, at the bottom, because they are what members tag their own decks with.
  #
  # Two queries rather than one relation carrying `includes`, and the reason is the GROUP BY.
  # `includes` on a grouped relation flips to `eager_load`, which JOINs `cards` and adds every one
  # of its columns to the SELECT list while the GROUP BY names only `archetypes.id` — a query the
  # database is entitled to refuse and, worse, one whose per-row result is arbitrary where it does
  # not. So the order is decided in SQL over ids alone, the records are loaded and preloaded in a
  # second query, and Ruby puts them back in the order the first decided. DecksController#compare
  # already re-sorts a `where(key: keys)` load against the order its caller asked for, for the
  # same reason: `IN (…)` promises nothing about order.
  def page_of(scope)
    ids = scope.left_joins(:tournament_standings)
      .group("archetypes.id")
      .order(Arel.sql("COUNT(tournament_standings.id) DESC"), :name)
      .offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      .pluck("archetypes.id")

    Archetype.where(id: ids).preload(:primary_card, :secondary_card)
      .sort_by { |archetype| ids.index(archetype.id) }
  end

  # to_s first: `?page[]=1` hands over an Array and `?page[a]=b` an
  # ActionController::Parameters, neither of which answers to_i. A session is required to reach
  # this action today, which makes the shape less likely rather than impossible — a member's own
  # bookmark or a link-checker can produce it just as well, and the NoMethodError would be a 500.
  def requested_page
    [ params[:page].to_s.to_i, 1 ].max
  end
end
