class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::Flash
  include Phlex::Rails::Helpers::ImageTag
  include Phlex::Rails::Helpers::NumberToCurrency
  include Phlex::Rails::Helpers::TurboStreamFrom
  include Phlex::Rails::Helpers::CollectionSelect
  include Phlex::Rails::Helpers::ControllerName
  include Phlex::Rails::Helpers::Localize
  include Phlex::Rails::Helpers::CSRFMetaTags
  include Phlex::Rails::Helpers::CSPMetaTag
  include Phlex::Rails::Helpers::StyleSheetLinkTag
  include Phlex::Rails::Helpers::JavaScriptImportmapTags

  extend Phlex::Rails::HelperMacros

  register_value_helper :current_user
  register_value_helper :user_signed_in?
end
