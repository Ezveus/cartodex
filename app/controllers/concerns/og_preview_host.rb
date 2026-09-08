# What a link to this page looks like when it is pasted into a chat. Layouts::ApplicationLayout
# renders Ui::OgTags on *every* page, so this never answers nil: the default is the site payload,
# whose image is the committed public/og-default.jpg, and an action replaces it by assigning
# @og_payload — which it may only do for a subject that is publicly readable.
#
# The assignment lives in the action rather than in an override here, next to the `authorize` that
# licensed it, and after whatever `includes` that action set up: Og::DeckPayload reads the deck's
# cards and its archetype's two member cards, so building it against an unpreloaded record is how
# this feature would quietly add queries to the app's most expensive pages.
#
# A concern rather than a method on ApplicationController for the reason SearchOverlayHost is one,
# and the comment there says it best: Layouts::ApplicationLayout has two hosts, and
# Oauth::AuthorizationsController does not descend from ApplicationController. A layout helper
# missing on the second host is a 500 on the consent screen and nowhere else. Both mechanisms are
# needed — `helper_method` here, and `register_value_helper :og_preview` on ApplicationComponent —
# because the first exposes it from the controller and the second is what lets a Phlex component
# call it by name.
module OgPreviewHost
  extend ActiveSupport::Concern

  included do
    helper_method :og_preview
  end

  private

  def og_preview
    @og_payload || Og::SitePayload.call
  end
end
