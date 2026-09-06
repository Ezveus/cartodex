module CardLabels
  # One human's answer about one card: which of the roles it plays, and — just as much a decision —
  # which it does not.
  #
  # A save is a statement about the **whole card** rather than about the box that moved, so every
  # role left unticked is written as a `curated` refusal. That is what makes CardLabels::RoleSuggester
  # leave the card alone afterwards: it never examines a pair carrying a curated row. Nothing is
  # deleted, because a deletion reads as "nobody has looked at this yet", which is exactly what
  # stops being true the moment somebody has.
  #
  # It lives in a service and not in Admin::CardRolesController for the reason every other write in
  # this app does — and for one that is specific to SQLite: `serialized_transaction` is where the
  # app's BEGIN IMMEDIATE lives, so a second admin saving the same fingerprint waits for the first
  # instead of racing it into the (card_label_id, fingerprint) UNIQUE index.
  class RoleDecision < ApplicationService
    def initialize(fingerprint:, card:, ticked:)
      @fingerprint = fingerprint
      @card = card
      @ticked = Array(ticked).map(&:to_s)
    end

    def call
      serialized_transaction do
        CardLabel.roles.each do |label|
          assignment = CardLabelAssignment.find_or_initialize_by(card_label: label,
                                                                 fingerprint: @fingerprint)
          assignment.update!(source: "curated", rejected: @ticked.exclude?(label.slug), card: @card)
        end
      end
    end
  end
end
