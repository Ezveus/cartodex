class StyleguideController < ApplicationController
  def show; end

  private

  # The reference page renders the real Search::Spotlight to document it, so it already has the
  # one spotlight a page is allowed.
  def search_overlay?
    false
  end
end
