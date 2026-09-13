class SearchCardsTool < McpTool
  MAX_LIMIT = 50

  description "Search the card database by name substring, set code and/or collector number. Give at least one of them, as separate arguments: a printing reference typed as one string (\"POR 56\") goes in set_code plus set_number, never in query. Returns matching cards with their ids, capped at #{MAX_LIMIT} and unordered — a full result is not distinguishable from a truncated one, so narrow rather than page."
  input_schema(
    properties: {
      query: { type: "string", description: "Case-insensitive substring of the card name. Not parsed: it never contains a set code or a number" },
      set_code: { type: "string", description: "Set code, matched case-insensitively (e.g. \"por\")" },
      set_number: {
        type: [ "string", "integer" ],
        description: "Collector number, matched exactly and as text (e.g. \"86\" or \"GG12\"). Scoped to a set only when set_code is given too"
      },
      limit: { type: "integer", description: "Max results (default 20, capped at 50; a value below 1 returns 1)" }
    },
    required: []
  )

  # Set plus number identifies exactly one printing, so the caller is not required to
  # know the name — but the refusal below tests `blank?` and not `nil?`, because
  # Card.name_matching("") compiles to LIKE '%%' and answers a criterion-less call
  # with the whole catalogue, truncated to `limit`.
  def self.call(server_context:, query: nil, set_code: nil, set_number: nil, limit: 20)
    if query.blank? && set_code.blank? && set_number.blank?
      return error_text("Error: give at least one of query, set_code or set_number.")
    end

    scope = Card.all
    scope = scope.name_matching(query) if query.present?
    # Card.in_set_code, not a `where` spelled out here: CardSearchable#card_set_code? asks the
    # same scope whether a token *is* a set code, and the two questions have to be one query or
    # the page and this tool answer differently — see the note on the scope.
    scope = scope.in_set_code(set_code) if set_code.present?
    # Matched as text: collector numbers like "GG12" exist and none is zero-padded, so there is
    # no integer to cast to. `.to_s` accepts the integer the schema allows; `squish` and not
    # `strip` because a copy-paste from a web page carries U+00A0, which String#strip leaves in
    # place — the same Unicode class NameNormalizable.normalize_for_match already folds.
    scope = scope.where(set_number: set_number.to_s.squish) if set_number.present?

    cards = scope.limit(limit.to_i.clamp(1, MAX_LIMIT)).map do |card|
      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number, card_type: card.card_type }
    end
    text(cards.to_json)
  end
end
