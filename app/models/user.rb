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

  def self.generate_api_token
    SecureRandom.base58(24)
  end

  def self.digest_api_token(raw)
    Digest::SHA256.hexdigest(raw)
  end

  # Returns the user matching a presented raw token, or nil. Lookup is by
  # digest of the presented value, so the stored secret is never compared
  # in plaintext and the query does not leak timing about the real token.
  def self.authenticate_api_token(raw)
    return if raw.blank?

    find_by(api_token_digest: digest_api_token(raw))
  end

  # Generates a new token, stores only its digest, and returns the raw token.
  # The raw value is shown only here (never persisted), so it cannot be
  # retrieved later — only rotated.
  def regenerate_api_token
    raw = self.class.generate_api_token
    update!(api_token_digest: self.class.digest_api_token(raw))
    raw
  end
end
