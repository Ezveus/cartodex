require "test_helper"

class Admin::CardLabelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # There is no admin fixture: the panel's tests promote users(:one), which is what
    # Admin::StandardPoolsControllerTest does.
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
    @type_label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type",
                                    position: 10, source_query: "is:ace")
    @role_label = CardLabel.create!(slug: "gust", name: "Gust", family: "role", position: 10)
  end

  test "the index lists both families and their assignment counts" do
    @type_label.assignments.create!(fingerprint: "fp", source: "imported")

    get admin_card_labels_path

    assert_response :success
    # Ui::DataTable renders cells as divs, not <td>s (see Admin::StandardPoolsControllerTest's own
    # css_select(".data-table-row") for the same shape) — ".data-table-cell" is the real selector.
    assert_select ".data-table-cell", text: "ACE SPEC"
    assert_select ".data-table-cell", text: "Gust"
  end

  test "an admin creates a type label with its search token" do
    assert_difference "CardLabel.count", 1 do
      post admin_card_labels_path, params: {
        card_label: { slug: "radiant", name: "Radiant", family: "type", position: 20,
                      source_query: "is:radiant" }
      }
    end

    assert_redirected_to admin_card_labels_path
    assert_equal "is:radiant", CardLabel.find_by(slug: "radiant").source_query
  end

  # The asymmetry the whole design rests on: a role slug is referenced by code (stage 2's
  # suggestion rules), so one invented here would be a label no rule can ever propose.
  test "creating a role label is refused" do
    assert_no_difference "CardLabel.count" do
      post admin_card_labels_path, params: {
        card_label: { slug: "healing", name: "Healing", family: "role", position: 30 }
      }
    end

    assert_redirected_to admin_card_labels_path
    assert_match(/seeded/, flash[:alert])
  end

  test "deleting a role label is refused and deleting a type label is not" do
    assert_no_difference "CardLabel.count" do
      delete admin_card_label_path(@role_label)
    end

    assert_match(/seeded/, flash[:alert])

    assert_difference "CardLabel.count", -1 do
      delete admin_card_label_path(@type_label)
    end
  end

  # A role label is still editable: a typo in a name or a wrong display order is a correction, not
  # a new vocabulary entry.
  test "a role label's name and position stay editable" do
    patch admin_card_label_path(@role_label),
      params: { card_label: { name: "Gust (bench)", position: 40, family: "type" } }

    assert_equal "Gust (bench)", @role_label.reload.name
    assert_equal 40, @role_label.position
    assert_equal "role", @role_label.reload.family
  end

  # A third door onto the create/destroy refusal: importable? is just source_query.present?, so
  # patching one onto a role label would make it importable without ever creating a role label.
  test "patching a source_query onto a role label leaves it blank" do
    patch admin_card_label_path(@role_label),
      params: { card_label: { source_query: "is:gust", family: "type" } }

    assert_nil @role_label.reload.source_query
    assert_not @role_label.importable?
  end

  test "importing enqueues the job and records the import" do
    assert_difference [ "Import.count" ], 1 do
      assert_enqueued_with(job: CardLabels::ImportJob) do
        post import_admin_card_label_path(@type_label)
      end
    end

    assert_redirected_to admin_imports_path
    assert_equal "card_labels", Import.last.kind
  end

  # Only a label that says where to read it can be imported, and the screen must refuse rather
  # than enqueue a run that will fail with an ArgumentError from a service constructor.
  test "importing a label with no search token is refused before anything is enqueued" do
    assert_no_enqueued_jobs do
      post import_admin_card_label_path(@role_label)
    end

    assert_match(/no search token/, flash[:alert])
  end

  test "a non-admin cannot reach the screen" do
    sign_in users(:two)

    get admin_card_labels_path

    assert_redirected_to root_path
  end

  # A rename is a delete and a create at once, and stage 2 is what made that expensive: the
  # suggestion rules key on the slug. Measured before this guard existed — the human's decisions
  # stayed on the orphaned row, the next db:seed recreated the original empty, the suggester
  # re-proposed what the human had decided, and /archetypes/:id rendered two sections both titled
  # "Search".
  test "a role label's slug cannot be renamed" do
    patch admin_card_label_path(@role_label), params: { card_label: { slug: "deck-gust", name: "Gust" } }

    assert_equal "gust", @role_label.reload.slug
  end

  test "a type label's slug is ordinary data and stays editable" do
    patch admin_card_label_path(@type_label), params: { card_label: { slug: "ace", name: "ACE SPEC" } }

    assert_equal "ace", @type_label.reload.slug
  end
end
