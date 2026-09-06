# The archetype catalog and one archetype's metagame report. Everything here reads; nothing
# writes.
#
# Member-only for now. **Opening the two pages to visitors is seven edits, not three** — the
# three that make the route reachable, and four more that decide what a visitor then sees.
# An earlier version of this comment listed only the first three; the list below was produced by
# applying them for real and reading what broke and, worse, what did not. **No test asks for any
# of the last four.** Three of them are outright silent — skip them and the suite stays green
# while the page ships half-open — and the fourth fails the other way round, with a test that goes
# on passing in defence of a rule that has become false.
#
# Reachability — each of these is covered by a test that goes red if it is missing:
#
#   1. move `resources :archetypes` out of the `authenticate :user` block in config/routes.rb
#      (its comment there says "three edits" too, and has to be corrected with this one),
#   2. `include PubliclyReachable` here, with `publicly_reachable :index, :show`,
#   3. flip ArchetypePolicy#index?/#show? from `user.present?` to `true`.
#
# What a visitor then meets — the four nothing asks for:
#
#   4. a per-IP `rate_limit to: 60, within: 1.minute, unless: -> { user_signed_in? },
#      store: RateLimitStore, only: :index`, sized like tournaments#index's because #index is
#      the same shape and the same cost: a field debounced at 300 ms driving a paginated listing
#      behind a Turbo Frame. Deliberately absent today — no anonymous request can reach the route
#      while the resource sits inside the authenticate block, so nothing can exercise the limiter,
#      and a limiter nobody can exercise is a limiter nobody knows works.
#   5. `nav_link "Archetypes", archetypes_path, "archetypes"` in Ui::PublicNavbar. Without it a
#      visitor on /archetypes lights **zero** navbar entries — NavbarActiveSectionTest asserts
#      "exactly one is lit" per page it names, and it names no visitor archetype page, so the
#      hole is outside every assertion it makes.
#   6. Search::Global#archetype_scope: drop the `Archetype.none` branch. The trap here is the
#      opposite of a silent one — Search::GlobalTest's "a visitor gets no archetypes, and none
#      are queried for" keeps *passing* while defending a rule that has become false, so that
#      test has to be inverted in the same commit rather than merely watched.
#   7. the two archetype links a public page currently withholds, because a link to a sign-in
#      wall was worse than no link and stops being so on that day:
#      Tournaments::Standings::Row#archetype_badge drops its `if @viewer.present?` guard, and
#      Decks::PublicBadges starts passing `href: archetype_path(@deck.archetype)`.
#
# Test bookkeeping that goes with it, and that nothing else will remind anybody of: the two
# archetype rows in public_access_test.rb move from `owner_only_gets` to `public_gets`, and three
# tests asserting today's refusal have to be turned round — "a visitor is sent to sign in for both
# pages" here, and ArchetypePolicyTest's two nil-user assertions.
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
    #
    # `to_s` before the comparison, for the reason `requested_page` calls it: `?group[]=role` hands
    # over an Array and `?group[a]=b` an ActionController::Parameters, and only the exact String
    # "role" selects role mode — anything else is the grouping this report has always had, the
    # clamp `#index` makes for `?page=` and `MetagameScope` makes for `?pool=`.
    @stats = Archetypes::CardStats.call(
      standings: @scope.listed_standings,
      grouping: params[:group].to_s == "role" ? :role : :type
    )
    @performance = Archetypes::Performance.call(standings: @scope.standings)
  end

  private

  # Recorded standings descending, then name. Archetypes nobody has recorded a result for stay
  # listed, at the bottom, because they are what members tag their own decks with.
  #
  # `includes` and not `preload`, even beside the GROUP BY, and that is worth one line because the
  # obvious fear is wrong: `includes` only escalates to `eager_load` when something references the
  # included table (a `where`/`order` naming it, or an explicit `references`), and nothing here
  # does. Measured on this relation — with `Archetype.all` and with `Archetype.search`, which adds
  # `.distinct` and two more `left_joins` — `eager_loading?` is false, both associations come back
  # preloaded, and the whole page costs three queries. An earlier version of this method plucked
  # the ordered ids and re-loaded them in a second pass to dodge an escalation that does not
  # happen; it cost a query and a Ruby sort to defend against nothing.
  def page_of(scope)
    scope.left_joins(:tournament_standings)
      .group("archetypes.id")
      .order(Arel.sql("COUNT(tournament_standings.id) DESC"), :name)
      .offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      .includes(:primary_card, :secondary_card)
      .to_a
  end

  # to_s first: `?page[]=1` hands over an Array and `?page[a]=b` an
  # ActionController::Parameters, neither of which answers to_i. A session is required to reach
  # this action today, which makes the shape less likely rather than impossible — a member's own
  # bookmark or a link-checker can produce it just as well, and the NoMethodError would be a 500.
  def requested_page
    [ params[:page].to_s.to_i, 1 ].max
  end
end
