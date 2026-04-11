class CardSets::ImportJob < ApplicationJob
  queue_as :default

  def perform(url, user, import)
    result = CardSets::Importer.call(url)
    card_set = result[:card_set]
    import.update!(status: "completed")

    Turbo::StreamsChannel.broadcast_remove_to(
      user, :notifications,
      target: "importing-set-#{import.id}"
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
    import.update!(status: "failed", error_message: e.message)

    Turbo::StreamsChannel.broadcast_remove_to(
      user, :notifications,
      target: "importing-set-#{import.id}"
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
