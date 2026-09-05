require "test_helper"
require "rake"

class CardLabelsRakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task.clear
    Cartodex::Application.load_tasks
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    @card = cards(:honedge)
  end

  # A force: true rescrape can move a Pokémon's fingerprint. The assignment then points at a
  # fingerprint no card carries, the report can never join it, and the card silently loses its
  # label — which is exactly the drift Archetypes::FingerprintSync exists to repair out of band.
  test "it moves an assignment onto the card's current fingerprint" do
    assignment = @label.assignments.create!(fingerprint: "honedge_fp", card: @card, source: "imported")
    @card.update_column(:fingerprint, "honedge_fp_v2")

    run_task

    assert_equal "honedge_fp_v2", assignment.reload.fingerprint
  end

  # The task aborts (non-zero exit) whenever it has something to report, on purpose, the same
  # contract standard_pools:backfill_anchors uses to fail a boot. abort raises SystemExit *through*
  # capture_io without letting it return, so the report is read back off $stdout captured by hand
  # (see run_task/printed below) rather than off a captured-output return value.
  test "an assignment with no card to read is reported, not guessed" do
    @label.assignments.create!(fingerprint: "orphan_fp", source: "imported")

    assert_raises(SystemExit) { run_task }

    assert_match "orphan_fp", printed
  end

  # Writing through would break the UNIQUE key half way into a run and leave the rest unexamined.
  test "a move that would collide with an existing decision is reported, not written" do
    kept = @label.assignments.create!(fingerprint: "doublade_fp", source: "curated")
    moving = @label.assignments.create!(fingerprint: "honedge_fp", card: @card, source: "imported")
    @card.update_column(:fingerprint, "doublade_fp")

    assert_raises(SystemExit) { run_task }

    assert_equal "honedge_fp", moving.reload.fingerprint
    assert_equal "curated", kept.reload.source
    assert_match "doublade_fp", printed
  end

  # The fingerprint assertion is the load-bearing half: the task's only write path is
  # update_column, which does not bump updated_at in this Rails version, so a
  # maximum(:updated_at) assertion here would pass identically whether the resolved assignment was
  # correctly skipped or wrongly moved onto some other fingerprint — verified directly:
  # update_column-ing this very row to a wrong fingerprint left maximum(:updated_at) unchanged.
  # The printed-output assertions back the test's other claim, that a clean run says nothing
  # beyond its own moved count. The rescue exists because a SystemExit here would itself be the
  # bug (a clean run must not abort) and minitest treats SystemExit as a passthrough it never
  # turns into a failure — left unrescued, a regression here would kill the whole suite instead of
  # failing this one test.
  test "it says nothing and changes nothing when every assignment resolves" do
    assignment = @label.assignments.create!(fingerprint: @card.fingerprint, card: @card, source: "imported")

    begin
      assert_no_changes -> { assignment.reload.fingerprint } do
        run_task
      end
    rescue SystemExit
      flunk "resync_fingerprints reported something for an assignment that already resolved:\n#{printed}"
    end

    assert_match "Moved 0 assignments.", printed
    assert_no_match "could not be moved", printed
  end

  private

  # Named run_task, not run: Minitest::Test#run is the framework's own method for driving a test
  # through setup and teardown, defined public on the superclass. A same-named private method here
  # would override it for this whole class rather than merely helping one test, and the runner's
  # explicit-receiver call (`instance.run`) would then raise NoMethodError on every test in the file
  # — measured, not assumed.
  #
  # Redirects $stdout by hand rather than using capture_io: capture_io's return value depends on
  # its block returning normally, and abort raises SystemExit out of that block instead — the
  # exception propagates straight past capture_io's own return statement, taking the captured
  # string with it. Stashing the StringIO on an ivar keeps it readable after the raise.
  def run_task
    original_stdout = $stdout
    $stdout = @printed = StringIO.new
    Rake::Task["card_labels:resync_fingerprints"].tap(&:reenable).invoke
  ensure
    $stdout = original_stdout
  end

  def printed
    @printed.string
  end
end
