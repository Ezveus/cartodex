module Oauth
  class TokensController < Doorkeeper::TokensController
    include ResourceIndicatorEnforcement
  end
end
