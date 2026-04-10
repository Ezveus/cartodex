class CardSets::ImportJob < ApplicationJob
  queue_as :default

  def perform(url, user, import_id)
    result = CardSets::Importer.call(url)
    card_set = result[:card_set]

    Turbo::StreamsChannel.broadcast_remove_to(
      user, :notifications,
      target: "importing-set-#{import_id}"
    )

    Turbo::StreamsChannel.broadcast_append_to(
      [ user, :notifications ],
      target: "flash-messages",
      html: <<~HTML
        <div class="flash flash-notice" data-controller="flash">
          Set "#{ERB::Util.html_escape(card_set.name)}" imported: #{result[:imported]} cards.
        </div>
      HTML
    )
  rescue => e
    Turbo::StreamsChannel.broadcast_remove_to(
      user, :notifications,
      target: "importing-set-#{import_id}"
    )

    Turbo::StreamsChannel.broadcast_append_to(
      [ user, :notifications ],
      target: "flash-messages",
      html: <<~HTML
        <div class="flash flash-alert" data-controller="flash">
          Set import failed: #{ERB::Util.html_escape(e.message)}
        </div>
      HTML
    )
  end
end
