# Whether this page shows the "use Cartodex as a search engine" announcement — and, when it does,
# the claim that it has now been shown. See
# docs/superpowers/specs/2026-10-07-browser-search-engine-design.md.
#
# Asked by Ui::FlashMessages, so only a response that renders the layout can claim it. Three such
# responses never reach the member's eyes and must not burn it:
#
# - a prefetch: Turbo 8 fetches every link on hover (X-Sec-Purpose), and Chrome itself prefetches
#   and prerenders pages it expects the member to open (Sec-Purpose, e.g. the root from the
#   omnibox) — either would claim the announcement in a page nobody may ever look at;
# - a Turbo Frame request: the layout is a Phlex lambda, so a frame request renders it whole and
#   Turbo keeps only the frame;
# - anything but a GET.
#
# A concern, like SearchOverlayHost and OgPreviewHost, because Layouts::ApplicationLayout has two
# hosts — ApplicationController's descendants and Oauth::AuthorizationsController — and a helper
# missing on the second is a 500 on the consent screen and nowhere else.
module SearchEngineAnnouncementHost
  extend ActiveSupport::Concern

  included do
    helper_method :search_engine_announcement?
  end

  private

  def search_engine_announcement?
    user_signed_in? &&
      request.get? &&
      !turbo_frame_request? &&
      !prefetch_request? &&
      current_user.claim_search_engine_announcement!
  end

  # Turbo's hover prefetch sends X-Sec-Purpose; the browser's own prefetch and prerender send
  # Sec-Purpose, whose value may carry more than one token ("prefetch;prerender").
  def prefetch_request?
    [ request.headers["X-Sec-Purpose"], request.headers["Sec-Purpose"] ]
      .any? { |purpose| purpose.to_s.include?("prefetch") }
  end
end
