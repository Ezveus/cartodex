class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :collections, dependent: :destroy
  has_many :cards, through: :collections
  has_many :decks, dependent: :destroy
  has_many :imports, dependent: :destroy
  has_many :tournament_profiles, dependent: :destroy
  has_many :tournaments, dependent: :destroy

  # Lifetime options offered when generating a token. nil means "never expires",
  # stored as a NULL api_token_expires_at. This Hash is the single definition of
  # both the allowed keys and the default, so the model and the form can never
  # disagree about what "default" means.
  TOKEN_LIFETIMES = { "30d" => 30.days, "90d" => 90.days, "1y" => 1.year, "never" => nil }.freeze
  DEFAULT_LIFETIME_KEY = "90d"

  def self.generate_api_token
    SecureRandom.base58(24)
  end

  def self.digest_api_token(raw)
    Digest::SHA256.hexdigest(raw)
  end

  # Returns the user matching a presented raw token, or nil. Lookup is by
  # digest of the presented value, so the stored secret is never compared
  # in plaintext and the query does not leak timing about the real token.
  # An expired token is rejected before its usage is recorded: expiry must
  # leave no trace of use.
  def self.authenticate_api_token(raw)
    return if raw.blank?

    user = find_by(api_token_digest: digest_api_token(raw))
    return if user.nil? || user.api_token_expired?

    user
  end

  # Generates a new token, stores only its digest, and returns the raw token.
  # The raw value is shown only here (never persisted), so it cannot be
  # retrieved later — only rotated. `expires_in` of nil means never expires.
  def regenerate_api_token(expires_in: TOKEN_LIFETIMES.fetch(DEFAULT_LIFETIME_KEY))
    raw = self.class.generate_api_token
    now = Time.current
    update!(
      api_token_digest: self.class.digest_api_token(raw),
      api_token_created_at: now,
      api_token_expires_at: expires_in && now + expires_in,
      api_token_last_used_at: nil
    )
    raw
  end

  # Leaves the user with no token at all, rather than an unusable one.
  def revoke_api_token!
    update!(
      api_token_digest: nil,
      api_token_created_at: nil,
      api_token_expires_at: nil,
      api_token_last_used_at: nil
    )
  end

  def api_token?
    api_token_digest.present?
  end

  def api_token_expired?
    api_token_expires_at.present? && api_token_expires_at.past?
  end
end
