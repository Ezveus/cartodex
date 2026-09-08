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
#   4. the per-IP `rate_limit` below. Sized like tournaments#index's because #index is the same
#      shape — a field debounced at 300 ms driving a paginated listing behind a Turbo Frame —
#      and, at 5 queries measured on the production dump, a cheaper one. #show gets none,
#      deliberately: its two selects auto-submit, so a click is a full page load of **16
#      queries / ~31 ms / 85 KB** for a visitor (17 with a session, which the flat-cost test
#      pins) — the app's largest uncapped anonymous response — but that is still one request
#      per deliberate click and not one per keystroke, which is the line decks#show and
#      tournaments#show sit on the same side of. The counter-argument is written down in
#      docs/architecture/public-surface.md rather than left out: decks#export is also one
#      click and *is* capped, at a third of the cost. ArchetypesRateLimitTest pins both halves.
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

  # An explicit `name:`, as every other limiter in the app carries: Rails keys a limiter on
  # ["rate-limit", scope, name, by] with `scope` defaulting to controller_path, so with one
  # limiter on one action the name buys nothing today — #show is not rationed because no
  # limiter runs on it at all, not because this budget is separate. It starts mattering the day
  # a second limiter lands on this controller, which is why it is spelled rather than left to
  # the default.
  INDEX_RATE_LIMIT_TO = 60
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: INDEX_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "archetypes-index", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :index

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
