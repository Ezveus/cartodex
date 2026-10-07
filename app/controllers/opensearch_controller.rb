# The OpenSearch description a browser reads to offer Cartodex as a search engine, linked from
# every page's <head> by Layouts::ApplicationLayout. Chrome honours that link only on the site's
# root and registers the engine as inactive until the member activates it — which is why
# /settings explains the manual setup as well.
#
# ActionController::Base rather than ApplicationController: the document is the same for every
# caller and reads no session, so there is nothing to authenticate or authorize. The host comes
# from the request, as in Oauth::MetadataController, so each environment advertises itself.
class OpensearchController < ActionController::Base
  def show
    render xml: description, content_type: "application/opensearchdescription+xml"
  end

  private

  def description
    Nokogiri::XML::Builder.new(encoding: "UTF-8") { |xml|
      xml.OpenSearchDescription(xmlns: "http://a9.com/-/spec/opensearch/1.1/") do
        xml.ShortName "Cartodex"
        xml.Description "Search decks, cards, tournaments and archetypes on Cartodex"
        xml.InputEncoding "UTF-8"
        xml.Image("#{root_url.chomp('/')}/icon-32.png", width: 32, height: 32, type: "image/png")
        # The ⌘K spotlight's own endpoint: opened as a page, it renders the same results.
        xml.Url(type: "text/html", method: "get", template: "#{search_url}?q={searchTerms}")
      end
    }.to_xml
  end
end
