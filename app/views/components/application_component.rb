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

  delegate_missing_to :helpers
end
