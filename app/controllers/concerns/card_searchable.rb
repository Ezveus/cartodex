module CardSearchable
  extend ActiveSupport::Concern

  private

  def apply_card_name_filter(scope, query)
    tokens = query.split(/\s+/)
    number = tokens.pop if tokens.length > 1 && tokens.last.match?(/\A\d+\z/)
    code   = tokens.pop if tokens.length > 1 && card_set_code?(tokens.last)
    name   = tokens.join(" ")

    scope = scope.merge(Card.name_matching(name)) if name.present?
    scope = scope.where("UPPER(cards.set_name) = ?", code.upcase) if code
    scope = scope.where(set_number: number) if number
    scope
  end

  def card_set_code?(token)
    token.match?(/\A[a-zA-Z]{2,5}\z/) &&
      CardSet.where("UPPER(code) = ?", token.upcase).exists?
  end
end
