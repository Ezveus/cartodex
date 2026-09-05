# Run one admin "import this label from Limitless" against an Import row.
#
# Enqueued with ids rather than records, for the reason Tournaments::StandingListImportJob is: a
# label can be deleted from the admin panel while the run is queued, and a record handed to a job
# that no longer exists raises ActiveRecord::DeserializationError *before* #perform is entered,
# where the rescue below cannot see it — leaving the Import at "pending" forever, with
# Admin::ImportsController#retry refusing this kind and no other way to clear it.
class CardLabels::ImportJob < ApplicationJob
  class LabelDeleted < StandardError; end

  queue_as :default

  def perform(import_id, card_label_id, user_id)
    # An Import deleted mid-flight is an ordinary lookup miss: there is nowhere left to report to.
    import = Import.find_by(id: import_id) or return
    user = User.find_by(id: user_id)

    label = CardLabel.find_by(id: card_label_id)
    raise LabelDeleted, "That card label no longer exists." if label.nil?

    finish(import, user, CardLabels::Importer.call(label), label)
  rescue StandardError => e
    report_failure(import, user, e)
  end

  private

  def finish(import, user, result, label)
    import.update!(status: "completed", error_message: summarise(result))
    broadcast(user, "flash-notice", %(Import of "#{label.name}" finished: #{outcome(result)}.))
  end

  # Every clause is stated only when it applies: a run with nothing missing should not have to
  # explain a zero, and a run that quietly skipped half its cards must not read like one that had
  # nothing to skip. "Already decided", not "already labelled": a curated row with `rejected: true`
  # counts toward already_present too, and calling a human's refusal "labelled" would report the
  # opposite of what happened.
  def outcome(result)
    parts = [ "#{result.created} #{"card".pluralize(result.created)} labelled" ]
    parts << "#{result.already_present} already decided" if result.already_present.positive?
    parts << "#{result.missing_printings.size} not in the catalogue" if result.missing_printings.any?
    parts.join(", ")
  end

  def summarise(result)
    lines = [ outcome(result) ]
    lines << "read #{result.read_count} of an announced #{result.announced_count}" unless result.complete?
    if result.missing_printings.any?
      lines << "#{result.missing_printings.size} #{"printing".pluralize(result.missing_printings.size)} " \
               "not in the catalogue: #{result.missing_printings.join(", ")}"
    end
    if result.unfingerprinted.any?
      lines << "#{result.unfingerprinted.size} skipped for having no fingerprint: " \
               "#{result.unfingerprinted.join(", ")}"
    end
    # Worded to claim no more than the run can prove: this is usually a printing the source
    # dropped, but it is also what an earlier-labelled card shows after it loses its fingerprint on
    # a rescrape — its printing may still be listed, just no longer resolvable to the fingerprint
    # this row was written under. Either way the run kept it rather than deleting it.
    if result.unlisted_fingerprints.any?
      lines << "#{result.unlisted_fingerprints.size} " \
               "#{"assignment".pluralize(result.unlisted_fingerprints.size)} the source no longer " \
               "lists or this run could not resolve, kept: #{result.unlisted_fingerprints.join(", ")}"
    end
    lines.join("\n")
  end

  def report_failure(import, user, error)
    return if import.nil?

    import.update!(status: "failed", error_message: error.message)
    broadcast(user, "flash-alert", %(Import of "#{import.label}" failed: #{error.message}))
  end

  def broadcast(user, css_class, message)
    return if user.nil?

    Turbo::StreamsChannel.broadcast_append_to(
      user, :notifications,
      target: "flash-messages",
      html: %(<div class="flash #{css_class}">#{ERB::Util.html_escape(message)}</div>)
    )
  end
end
