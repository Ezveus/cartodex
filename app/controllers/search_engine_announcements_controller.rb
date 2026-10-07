# The announcement's own "I was seen" call, sent by announcement_controller.js when the alert
# connects to a page actually on screen. See User#acknowledge_search_engine_announcement! for why
# the server cannot decide that while rendering. Idempotent: a second call writes nothing.
class SearchEngineAnnouncementsController < ApplicationController
  def destroy
    current_user.acknowledge_search_engine_announcement!
    head :no_content
  end
end
