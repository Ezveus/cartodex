module Search
  # The spotlight's Turbo Frame. Split from the list it wraps so the list can also be rendered
  # outside a frame (the styleguide), without a second element carrying FRAME_ID.
  class ResultsView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "search_results".freeze

    def initialize(results:)
      @results = results
    end

    def view_template
      turbo_frame_tag(FRAME_ID) do
        render ResultsList.new(results: @results)
      end
    end
  end
end
