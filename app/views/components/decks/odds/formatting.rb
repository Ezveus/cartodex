module Decks
  module Odds
    # One place decides how a probability is spelled on this page.
    #
    # The value arrives already rounded to two places and already in percent, from
    # Decks::Odds::Report.percent — so this is formatting and not rounding, and
    # deck_odds_controller.js spells the same stored number the same way with `toFixed(2)`. That is
    # what keeps a server-rendered cell and the one the controls move from ever disagreeing about a
    # digit, which two independent roundings would eventually do.
    #
    # `Kernel.format` and not a bare `format`: phlex-rails defines a zero-argument `format` on every
    # component, which shadows Kernel#format and answers an ArgumentError here.
    module Formatting
      def percent(value) = Kernel.format("%.2f %%", value)
    end
  end
end
