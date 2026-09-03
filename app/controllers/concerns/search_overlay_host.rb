# Whether the page should carry Search::Overlay — the dialog behind the navbar's search trigger,
# which is what makes the spotlight reachable from anywhere.
#
# Search::ResultsView::FRAME_ID is a DOM id and Turbo resolves a frame by id, so a page that
# already renders a Search::Spotlight must not get a second one: the overlay's results would land
# in the inline panel. Those pages answer false; the trigger is rendered either way and simply
# focuses the field they already show.
#
# A concern rather than a method on ApplicationController because Layouts::ApplicationLayout has
# two hosts: every ApplicationController descendant, and Oauth::AuthorizationsController, which
# descends from Doorkeeper's. A layout helper missing on the second one is a 500 on the consent
# screen and nowhere else.
module SearchOverlayHost
  extend ActiveSupport::Concern

  included do
    helper_method :search_overlay?
  end

  private

  def search_overlay?
    true
  end
end
