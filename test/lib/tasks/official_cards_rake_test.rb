require "test_helper"
require "rake"
require "tmpdir"

class OfficialCardsRakeTest < ActiveSupport::TestCase
  FIXTURES = Rails.root.join("test/fixtures/files/official_cards")

  setup do
    Rake::Task.clear
    Cartodex::Application.load_tasks
  end

  def with_fragments(*names)
    Dir.mktmpdir do |dir|
      names.each { FileUtils.cp(FIXTURES.join("#{_1}.html"), File.join(dir, "#{_1}.html")) }
      yield dir
    end
  end

  # --- import -------------------------------------------------------------------------------

  test "import reports this run's counts and does not abort on a clean directory" do
    with_fragments("30th_21", "30th_128") do |dir|
      run_task("official_cards:import", dir, "30th", "30C", "30th Celebration")
    end

    assert_match(/Imported 2\b/, printed)
    assert_equal 2, CardSet.find_by(code: "30C").cards.count
  end

  test "import exits non-zero when a card could not be written" do
    # `exit` raises SystemExit, which minitest treats as a passthrough that kills the whole run
    # rather than failing one test — hence assert_raises here and the hand-rolled $stdout capture
    # below, both copied from CardLabelsRakeTest for the same reason.
    with_fragments("30th_21", "30th_53") do |dir|
      broken = File.join(dir, "30th_53.html")
      File.write(broken, File.read(broken).sub(%r{<span>53/128[^<]*</span>}, "<span>53/128</span>"))

      assert_raises(SystemExit) do
        run_task("official_cards:import", dir, "30th", "30C", "30th Celebration")
      end
    end

    assert_match(/1 failed/, printed)
    assert_match "30th_53.html", printed
    # The run is not all-or-nothing: the card that parsed is in the database.
    assert Card.exists?(set_name: "30C", set_number: "21")
  end

  # --- rename_set ---------------------------------------------------------------------------

  test "rename_set moves the cards and the set row together" do
    with_fragments("30th_21") do |dir|
      run_task("official_cards:import", dir, "30th", "30C", "30th Celebration")
    end

    run_task("official_cards:rename_set", "30C", "CEL30")

    assert_equal "CEL30", Card.find_by(set_number: "21", name: "Greninja ex").set_name
    assert CardSet.exists?(code: "CEL30")
    assert_not CardSet.exists?(code: "30C")
  end

  test "rename_set moves a card the set never claimed" do
    # 44 catalogue printings carry a nil card_set_id, so the task has to walk
    # Card.where(set_name:) and not card_set.cards, or it renames the set row out from under
    # cards that keep the old code forever.
    Card.create!(
      name: "Orphan", card_type: "Trainer", set_name: "30C", set_number: "999", rarity: "Common"
    )

    run_task("official_cards:rename_set", "30C", "CEL30")

    # By name, not by number: a fixture already occupies set_number "999" in another set.
    assert_equal "CEL30", Card.find_by(name: "Orphan").set_name
  end

  test "rename_set refuses a target that only exists as a set_name" do
    # The wrong key here is card_sets.code: cards.set_name holds 54 codes against card_sets' 28,
    # the same asymmetry Card.in_set_code exists for. A target with cards but no set row would
    # pass a code-only check and then collide with index_cards_on_set_name_and_set_number.
    Card.create!(
      name: "Squatter", card_type: "Trainer", set_name: "CEL30", set_number: "21", rarity: "Common"
    )
    Card.create!(
      name: "Mover", card_type: "Trainer", set_name: "30C", set_number: "21", rarity: "Common"
    )
    CardSet.create!(code: "30C", name: "30th Celebration")

    assert_raises(SystemExit) { run_task("official_cards:rename_set", "30C", "CEL30") }

    assert_match(/CEL30/, printed)
    assert_equal "30C", Card.find_by(name: "Mover").set_name
    assert CardSet.exists?(code: "30C"), "the set row must not move when the cards cannot"
  end

  # Redirects $stdout by hand rather than using capture_io: capture_io's return value depends on
  # its block returning normally, and `exit` raises SystemExit straight past it, taking the
  # captured string with it.
  def run_task(name, *args)
    original_stdout = $stdout
    $stdout = @printed = StringIO.new
    Rake::Task[name].tap(&:reenable).invoke(*args)
  ensure
    $stdout = original_stdout
  end

  def printed
    @printed.string
  end
end
