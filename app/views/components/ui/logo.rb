module Ui
  # The app's reduced mark, posted inline as SVG rather than through an `image_tag` of
  # `public/icon-small.svg`. The reason is one colour: the mat in that file is `#0E1320`, which is
  # exactly `--ink-900`, which is exactly `.navbar`'s background — served as a file the mark's whole
  # body disappears into the bar it sits on, and an external SVG's fills are out of the page's
  # reach. Inline, the three fills become design tokens and follow the bar instead of fighting it.
  #
  # The cost of that decision is that the drawing now lives in two places: this component, and
  # `public/icon-small.svg`, which stays the favicon's source and is what `bin/rails icons:build`
  # rasterises. Nothing links them at runtime, so the geometry below is copied byte for byte from
  # that file — every x, y, width, height, rx and the group's transform — and
  # `test/components/ui/logo_test.rb` parses both sides and fails the moment they diverge. Change
  # the mark in one place and that test tells you about the other.
  class Logo < ApplicationComponent
    # Pixels, square. 26 is the navbar's size; the parameter exists because the styleguide and any
    # future larger placement need a different box, not a different drawing.
    def initialize(size: 26)
      @size = size
    end

    def view_template
      svg(
        class: "navbar-logo",
        width: @size.to_s,
        height: @size.to_s,
        # The viewBox is what makes `size:` a box rather than a scale: the geometry is authored
        # once at 512 and every rendered size is the same drawing.
        viewBox: "0 0 512 512",
        # Decorative. The brand link this sits inside already names the app, so announcing the mark
        # would read it out twice; `focusable="false"` is the other half of that, for the IE-era
        # behaviour of putting inline SVG in the tab order that some engines still honour.
        aria_hidden: "true",
        focusable: "false"
      ) do |s|
        # The tilted mat and its centre line. The tension between this -11 degree group and the
        # upright card outside it *is* the logo, so the transform is copied verbatim.
        s.g(transform: "rotate(-11 256 256)") do
          # --ink-700 rather than the source's --ink-900: one step up from the bar, so the mat
          # reads as a shape on it instead of as a hole in it.
          s.rect(x: "48", y: "112", width: "416", height: "304", rx: "32", fill: "var(--ink-700)")
          # The line moves up with the mat it sits on — at --ink-700 it would now be invisible
          # against it, the very failure this component was written to fix, one layer in.
          s.rect(x: "88", y: "280", width: "336", height: "18", rx: "9", fill: "var(--ink-500)")
        end
        # The active card, upright and outside the group. --flare is the token for the same red the
        # source hardcodes, so this one is a rename rather than a recolouring.
        s.rect(x: "196", y: "86", width: "120", height: "168", rx: "18", fill: "var(--flare)")
      end
    end
  end
end
