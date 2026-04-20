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
end
