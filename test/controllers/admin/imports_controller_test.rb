require "test_helper"

class Admin::ImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
  end

  # The decklist text is not stored anywhere — an Import carries a label, not a payload — so
  # there is nothing to re-run. Refused explicitly rather than left to fall through the case,
  # which destroys the old row and enqueues nothing.
  test "a field-list import cannot be retried" do
    import = users(:one).imports.create!(kind: "standing_list", label: "Ash's list", status: "failed")

    assert_no_difference -> { Import.count } do
      post retry_admin_import_path(import)
    end

    assert_redirected_to admin_imports_path
    assert_match(/cannot be retried/, flash[:alert])
    assert Import.exists?(import.id)
  end

  # Same class of reason one level up: a bulk run is defined by its deck id, archetype and event
  # filters, none of which the Import row keeps. Retry is now an allowlist of the two kinds whose
  # label really is the whole job, so this is refused by the rule rather than by a branch somebody
  # had to remember to add — the row survives and nothing is enqueued.
  test "a bulk standings import cannot be retried" do
    import = users(:one).imports.create!(kind: "limitless_standings", label: "Raging Bolt (deck 280)", status: "failed")

    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs do
        post retry_admin_import_path(import)
      end
    end

    assert_redirected_to admin_imports_path
    assert_match(/cannot be retried/, flash[:alert])
    assert Import.exists?(import.id)
  end

  # The search token lives on the CardLabel row, not on the Import, so retrying means running the
  # import again from the label. UNRETRYABLE_REASONS["card_labels"] is what makes that the admin's
  # answer instead of the generic fallback sentence — nothing else pins that key is reachable.
  test "a card-label import cannot be retried" do
    import = users(:one).imports.create!(kind: "card_labels", label: "ACE SPEC (is:ace)", status: "failed")

    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs do
        post retry_admin_import_path(import)
      end
    end

    assert_redirected_to admin_imports_path
    assert_match(/run it again from the label/, flash[:alert])
    assert Import.exists?(import.id)
  end

  # The allowlist has to keep saying yes to the two kinds that were always retryable. Inverting a
  # refusal chain is exactly the change that silently takes a working button away, so both live
  # branches are pinned rather than assumed.
  test "a deck import is still retried" do
    import = users(:one).imports.create!(kind: "deck", label: "Raging Bolt", status: "failed")

    assert_enqueued_with(job: ::Decks::ImportJob) do
      post retry_admin_import_path(import)
    end

    assert_redirected_to admin_imports_path
    assert_equal "Import retried.", flash[:notice]
    assert_not Import.exists?(import.id), "the retried row is replaced by the new one"
  end

  test "a card set import is still retried" do
    import = users(:one).imports.create!(kind: "card_set", label: "MEG", status: "failed")

    assert_enqueued_with(job: ::CardSets::ImportJob) do
      post retry_admin_import_path(import)
    end

    assert_redirected_to admin_imports_path
    assert_equal "Import retried.", flash[:notice]
    assert_not Import.exists?(import.id)
  end

  # The error cell used to be a title= tooltip. Ui::DataTable stacks into a data-label card grid
  # below 768px, where nothing hovers, so the full text of a bulk run's per-row failure list was
  # unreachable by construction on the mobile half of CI's sweep. It has to be *in the document*
  # and not in an attribute — which is what asserting on the <details> body checks, since a
  # title= would satisfy a bare assert_match against the response body just as well.
  test "the imports table discloses the whole error message, not just a tooltip" do
    message = (1..6).map { |n| "Row #{n}: 'Iron Hands ex PAR 70' is not a card this database knows." }.join("\n")
    users(:one).imports.create!(kind: "card_set", label: "MEG", status: "failed", error_message: message)

    get admin_imports_path

    assert_response :success

    summary = css_select("details.import-error > summary").first
    full = css_select("details.import-error p.import-error-full").first

    assert_not_nil summary, "a long error message is a disclosure, not a tooltip"
    assert_not_nil full
    assert_includes summary.text, "Row 1:"
    assert_not_includes summary.text, "Row 6:", "the collapsed row still shows only the truncation"
    assert_includes full.text, "Row 6:", "the last failure is in the document, not in a title="
  end

  # Undo is the only way back out of a bad run (D12), and its flash is the only report the admin
  # gets: the rows that survived are the half they have to go and look at by hand, so a claimed
  # count of zero and a claimed count of one must not read the same.
  test "undoing a bulk run destroys the unclaimed rows and names both counts" do
    claimed = create_standing("Brock", tournament_entry: tournament_entries(:one))
    unclaimed = create_standing("Misty")
    import = create_bulk_import(created_standing_ids: [ claimed.id, unclaimed.id ])

    post undo_admin_import_path(import)

    assert_redirected_to admin_imports_path
    assert_equal "Undid 1 standing; 1 was claimed and kept.", flash[:notice]
    assert_not TournamentStanding.exists?(unclaimed.id)
    assert TournamentStanding.exists?(claimed.id)
  end

  # No other kind of import records what it created, so there is nothing an undo could act on.
  # The action says so instead of letting the service's ArgumentError become a 500: the button is
  # not rendered for these rows, but the route is a POST any admin can reach by hand.
  test "an import of another kind cannot be undone" do
    import = users(:one).imports.create!(kind: "deck", label: "Raging Bolt", status: "completed")

    post undo_admin_import_path(import)

    assert_redirected_to admin_imports_path
    assert_match(/can be undone/, flash[:alert])
  end

  private

  # archetypes(:standings_marker) and no other fixture — see the note in test/fixtures/archetypes.yml.
  def create_standing(player_name, **attributes)
    tournaments(:one).standings.create!(
      player_name: player_name,
      division: "masters",
      archetype: archetypes(:standings_marker),
      created_by: @admin,
      **attributes
    )
  end

  def create_bulk_import(created_standing_ids:)
    @admin.imports.create!(
      kind: "limitless_standings",
      label: "Raging Bolt (deck 280)",
      status: "completed",
      created_standing_ids: created_standing_ids
    )
  end
end
