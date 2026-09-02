class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  protect_from_forgery with: :exception
  # Before authenticate_user!, so that even the redirect it issues carries the header.
  before_action :discourage_indexing
  before_action :authenticate_user!
  layout -> { Layouts::ApplicationLayout }

  private

  # Nothing in the app is indexable for now (decision 12 of the design). A header rather than
  # only a meta tag because it also covers what has no <head>: the JSON API and the image
  # proxy. Un-sharing a deck takes it off Cartodex at once and would not take it out of a
  # search engine for weeks, and /cards would publish a scraped catalog with its prices.
  def discourage_indexing
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
end
