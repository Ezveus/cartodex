# The archetype catalog and one archetype's metagame report. Everything here reads; nothing
# writes.
#
# **Public.** Both actions answer without a session, which took seven edits and not the obvious
# three — the list this comment used to carry as a to-do, kept here as the record of what it
# cost, because four of the seven are things no test asks for and three of those are outright
# silent:
#
#   1. `resources :archetypes` sits outside routes.rb's `authenticate :user` block,
#   2. `include PubliclyReachable` with `publicly_reachable :index, :show` below,
#   3. ArchetypePolicy#index?/#show? answer `true`.
#
# Those three are each covered by a test that goes red without them. The four that follow decide
# what a visitor then *meets*, and the suite would have stayed green with every one of them
# missing:
#
#   4. the two per-IP `rate_limit`s below — 60 on #index, 120 on #show. #show shipped without
#      one, on the argument that it is one request per deliberate click; that argument was
#      wrong, and measuring it is what settled the question. Turbo 8 prefetches on hover and
#      #index renders 24 row links: ten hovers produced ten full report loads, at 16 queries /
#      ~31 ms / 85 KB each. So the largest anonymous response in the app was reachable 24 times
#      by a cursor moving down a list. ArchetypesRateLimitTest pins both budgets and their
#      separation.
#   5. `nav_link "Archetypes"` in Ui::PublicNavbar. Without it a visitor on either page lights
#      **zero** navbar entries — NavbarActiveSectionTest asserts "exactly one is lit" per page
#      it names, and it named no visitor archetype page until this shipped.
#   6. Search::Global#archetype_scope dropped its `Archetype.none` branch. That was the trap of
#      the opposite kind: its test kept *passing* while defending a rule that had become false,
#      so it was inverted in the same commit rather than merely watched.
#   7. the two archetype links a public page withheld while /archetypes was a sign-in wall:
#      Tournaments::Standings::Row#archetype_badge no longer guards on `@viewer.present?`, and
#      Decks::PublicBadges grew a `linked:` keyword — **not** an unconditional href, since two
#      of its three callers render it inside an anchor of their own.
#
# The pages are `noindex` like everything else the app serves — XRobotsTagMiddleware and the
# layout's meta tag cover them for free. Discovery and SEO are #142, for the whole app at once;
# opening a page to visitors is not the same decision as inviting a crawler to it.
#
# There is no visitor-only view of either page, unlike Decks::PublicShowView, and that was
# checked rather than assumed: no component under app/views/components/archetypes/ reads
# current_user, user_signed_in?, a viewer or a policy. There is nothing to withhold.
class ArchetypesController < ApplicationController
  include Searchable
  include PubliclyReachable

  publicly_reachable :index, :show

  PER_PAGE = 24

  # Two limiters, two budgets, and the `name:` on each is what keeps them apart: Rails keys a
  # limiter on ["rate-limit", scope, name, by] with `scope` defaulting to controller_path, so one
  # shared name would mean a reader who exhausted the catalog could not open a report.
  # ArchetypesRateLimitTest asserts that in both directions.
  #
  # 60 for the catalog, the number tournaments#index and decks#shared carry for the reason those
  # two share it: a field debounced at 300 ms driving a paginated listing behind a Turbo Frame,
  # and at 5 queries the cheapest of the three.
  INDEX_RATE_LIMIT_TO = 60
  # **120 for the report — higher than the catalog, which reads backwards until the amplifier is
  # named.** This action is not one request per deliberate click, which is what an earlier
  # version of this comment claimed and what kept it uncapped: Turbo 8 prefetches on hover,
  # nothing in this app opts out (no `<meta name="turbo-prefetch">`, no `data-turbo-prefetch` on
  # the row links), and #index renders 24 of those links. Measured in a browser against the
  # production dump: **ten hovers produced ten full report loads**, at 16 queries / 85 KB each —
  # so a cursor sweeping the catalog, not a click, sets this action's peak rate, and four pages of
  # 24 rows put a thorough reader's own ceiling near 100/min. 120 clears that while capping one IP
  # at roughly 10 MB/min against the 2 MB/s a single client sustained uncapped.
  #
  # The alternative was to remove the amplifier instead of rationing it — `data-turbo-prefetch:
  # "false"` on Archetypes::IndexView's row link — and it is deliberately not taken here: prefetch
  # is what makes the catalog feel instant, and dropping it is a UX decision rather than a
  # protection one. `/tournaments` amplifies identically (measured: six hovers, six loads) and
  # tournaments#show is still uncapped; that is its own decision and not this one.
  SHOW_RATE_LIMIT_TO = 120
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: INDEX_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "archetypes-index", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :index

  rate_limit to: SHOW_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "archetypes-show", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :show

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
    #
    # `find_by!(slug:)` and not `find`: an archetype is addressed by its name, parameterized —
    # `Archetype#to_param` returns it, which is why the URL every page emits changed with no edit
    # to a single call site. The slug moves when the name moves and nothing records the old one:
    # a renamed archetype's links break, which is the decision recorded in
    # docs/superpowers/specs/2026-09-08-public-archetypes-and-slugs-design.md. It costs the same
    # one indexed query `find` did, so the flat-cost tests below are unmoved.
    @archetype = Archetype.preload(:primary_card, :secondary_card, :parent, :children)
                          .find_by!(slug: params[:id])
    authorize @archetype

    #
    # `params[:venue]` rides alongside rather than becoming a `where` here: MetagameScope's opening
    # comment promises it is the only place that answers which standings count, and the page's four
    # printed "N lists" agree *because* one object computes them. A filter applied in the
    # controller would have the selector print 118 while the report counted 98.
    @scope = Archetypes::MetagameScope.call(archetype: @archetype, pool_param: params[:pool],
                                            venue_param: params[:venue])
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
  # ActionController::Parameters, neither of which answers to_i. This action is reachable without
  # a session, so the shape arrives from anywhere — CardsController#index carries the same line
  # for the same reason, and PubliclyReachable rescues neither NoMethodError nor the 500 it
  # would be.
  def requested_page
    [ params[:page].to_s.to_i, 1 ].max
  end
end
