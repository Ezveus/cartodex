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

  # A bulk card add is the one kind whose payload *is* stored — the receipt holds every printing
  # and every before/after — so the generic fallback sentence ("what it was run from is not
  # stored") tells the admin the opposite of the truth while still matching /cannot be retried/.
  # What is refused here is replaying a *relative* add: run twice, it adds the copies twice. The
  # row is built failed on purpose, since a real one is completed and the status guard above would
  # answer first with a different message.
  test "a bulk card add cannot be retried, and says why in its own words" do
    import = users(:one).imports.create!(
      kind: "bulk_cards",
      label: "Collection — 5 copies over 3 printings",
      status: "failed"
    )

    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs do
        post retry_admin_import_path(import)
      end
    end

    assert_redirected_to admin_imports_path
    assert_match(/adds copies rather than setting them/, flash[:alert])
    assert_no_match(/what it was run from is not stored/, flash[:alert])
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

  # The receipt is the whole point of the row: it names every printing the run touched and what it
  # did to each. It is disclosed in the Label cell rather than in an eighth column, because
  # Ui::DataTable stacks into a data-label card grid below 768px and a new column is a layout
  # change this feature has no reason to make. Asserted on its *content* and not merely on the
  # presence of a <details>: `receipt` is a json column, so a view reading entry[:name] renders an
  # empty line per entry while every node-is-present assertion stays green — hence a persisted row,
  # re-read the way the view reads it.
  test "the imports table discloses what a bulk card add wrote" do
    users(:one).imports.create!(
      kind: "bulk_cards",
      label: "Collection — 2 copies over 1 printing",
      status: "completed",
      receipt: [ { card_id: cards(:honedge).id, set_name: "POR", set_number: "56",
                   name: "Honedge", quantity: 2, before: 1, after: 3 } ]
    )

    get admin_imports_path

    assert_response :success

    summary = css_select("details.import-receipt > summary").first
    body = css_select("details.import-receipt .import-receipt-list").first

    assert_not_nil summary, "the label is the summary of the disclosure"
    assert_not_nil body
    assert_includes summary.text, "Collection — 2 copies over 1 printing"
    assert_includes body.text, "Honedge"
    assert_includes body.text, "POR 56"
    assert_includes body.text, "1 \u2192 3"
  end

  # A deck receipt names the deck by key, because `decks.name` carries no uniqueness: two decks of
  # one member produced two rows whose labels were byte-identical and which pointed at neither.
  test "a deck receipt names the deck it wrote to, and a collection receipt names none" do
    deck = users(:one).decks.create!(name: "Rival", standard_pool: standard_pools(:twm_por))
    users(:one).imports.create!(
      kind: "bulk_cards", label: "Deck “Rival” — 1 copy over 1 printing", status: "completed",
      receipt: [ { card_id: cards(:honedge).id, set_name: "POR", set_number: "56", name: "Honedge",
                   quantity: 1, deck_key: deck.key, before: 0, after: 1,
                   owned_before: 0, owned_after: 0 } ]
    )

    get admin_imports_path

    assert_includes css_select("details.import-receipt .import-receipt-list").first.text, "Deck #{deck.key}"
  end

  # /admin/imports is unpaginated, which is pre-existing; a row rendering one <li> per printing is
  # not — measured, 52 rows of 58 printings took the page from 46 KB to 265 KB.
  test "a long receipt names the first twenty printings and counts the rest" do
    users(:one).imports.create!(
      kind: "bulk_cards", label: "Collection — 25 copies over 25 printings", status: "completed",
      receipt: Array.new(25) { |n|
        { card_id: cards(:honedge).id, set_name: "ZZY", set_number: n.to_s,
          name: "Probe #{n}", quantity: 1, before: 0, after: 1 }
      }
    )

    get admin_imports_path

    body = css_select("details.import-receipt .import-receipt-list").first
    assert_equal 21, body.css("li").size, "twenty printings plus the line that counts the rest"
    assert_includes body.text, "Probe 19"
    assert_not_includes body.text, "Probe 20"
    assert_includes body.text, "… and 5 more"
  end

  # Every other kind of import writes an empty receipt, which is most of the table. A <details>
  # whose body is empty invites a click that changes nothing, so the label stays plain text.
  test "an import with no receipt renders its label as plain text" do
    users(:one).imports.create!(kind: "card_set", label: "MEG", status: "completed")

    get admin_imports_path

    assert_response :success
    assert_empty css_select("details.import-receipt")
    assert_includes css_select(".data-table-cell[data-label='Label']").map(&:text), "MEG"
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
