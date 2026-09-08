require "test_helper"

# The mark is drawn in two places on purpose: `public/icon-small.svg` stays the favicon's source
# (rasterised by `bin/rails icons:build`), and Ui::Logo posts the same geometry inline so the fills
# can be design tokens instead of hex. Nothing but this test connects the two, so it is written as
# an anti-drift test rather than as a rendering test: it compares the component against the file,
# shape for shape, and only tolerates the three fills the recolouring exists for.
class Ui::LogoTest < ActiveSupport::TestCase
  SOURCE_PATH = Rails.root.join("public/icon-small.svg")

  # The recolouring, stated once and asserted literally below. The mat carries the whole point:
  # `#0E1320` is `--ink-900`, which is exactly `.navbar`'s background, so the source mark's body is
  # invisible on the bar it is posted to.
  EXPECTED_FILLS = {
    "#0E1320" => "var(--ink-700)",  # the mat
    "#28324A" => "var(--ink-500)",  # the centre line
    "#DD2C16" => "var(--flare)"     # the active card
  }.freeze

  setup do
    @source = parse(File.read(SOURCE_PATH))
    @component = parse(Ui::Logo.new.call)
  end

  # Counted on both sides and compared. Walking only the component's shapes and looking each one up
  # in the source is the vacuous version of this test: it passes a component that drops a shape.
  test "the component draws exactly the source's three shapes" do
    assert_equal 3, shapes(@source).size, "the source mark should hold three shapes"
    assert_equal 3, shapes(@component).size, "the component should hold three shapes"
    assert_equal shapes(@source).size, shapes(@component).size
  end

  # Every attribute except the fill, so a changed rx or a shape drawn at the wrong y is a failure
  # and not a detail. The root <svg> is deliberately outside this comparison — its width/height are
  # the one thing `size:` is allowed to move.
  test "the geometry agrees shape for shape with the source" do
    shapes(@source).zip(shapes(@component)).each_with_index do |(source_shape, component_shape), index|
      assert_equal source_shape.name, component_shape.name, "shape #{index} has the wrong element name"
      assert_equal geometry(source_shape), geometry(component_shape), "shape #{index} has drifted from the source"
    end
  end

  # Compared as a whole string: the tilt of the mat against the upright card is the logo, and a
  # transform re-spelled with commas or a different centre is a different drawing.
  test "the group's transform is the source's, spelled the same way" do
    assert_equal 1, @component.xpath("//g").size
    assert_equal @source.at_xpath("//g")["transform"], @component.at_xpath("//g")["transform"]
  end

  # Asserted against literal token names rather than against "differs from the source": the whole
  # failure this component prevents is a fill that differs as a string and is identical as a colour.
  test "each shape carries the token its source fill maps to" do
    shapes(@source).zip(shapes(@component)).each do |source_shape, component_shape|
      expected = EXPECTED_FILLS.fetch(source_shape["fill"])
      assert_equal expected, component_shape["fill"], "#{source_shape["fill"]} should be posted as #{expected}"
    end
  end

  # The one colour the component may never emit, in either spelling, anywhere. A regex rather than
  # a parse because this guards the whole output, including any attribute a future edit adds.
  test "nothing in the output is the navbar's own background" do
    html = Ui::Logo.new.call

    assert_no_match(/fill="[^"]*--ink-900[^"]*"/i, html)
    assert_no_match(/fill="[^"]*#0E1320[^"]*"/i, html)
  end

  # `size:` is a box, not a scale: the viewBox is what keeps the geometry above independent of it.
  test "size sets the rendered box and leaves the viewBox alone" do
    svg = parse(Ui::Logo.new(size: 40).call).at_xpath("//svg")

    assert_equal "40", svg["width"]
    assert_equal "40", svg["height"]
    assert_equal "0 0 512 512", svg["viewBox"]
  end

  test "the default size is 26 and the navbar's hook is on the root element" do
    svg = parse(Ui::Logo.new.call).at_xpath("//svg")

    assert_equal "26", svg["width"]
    assert_equal "26", svg["height"]
    assert_equal "navbar-logo", svg["class"]
    # Decorative: the brand link beside it already names the app, so a screen reader announcing
    # the mark too would read it twice.
    assert_equal "true", svg["aria-hidden"]
    assert_equal "false", svg["focusable"]
  end

  private

  # The source file declares the SVG namespace and the component does not, so the namespaces are
  # dropped rather than reconciled — this test is about shapes, not about how each side is served.
  def parse(markup)
    Nokogiri::XML(markup).tap(&:remove_namespaces!)
  end

  # Document order, which both sides share: mat, line, card.
  def shapes(doc)
    doc.xpath("//rect")
  end

  def geometry(shape)
    shape.attributes.transform_values(&:value).except("fill")
  end
end
