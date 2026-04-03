# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_03_104925) do
  create_table "abilities", force: :cascade do |t|
    t.integer "card_id", null: false
    t.string "name"
    t.text "effect"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_abilities_on_card_id"
  end

  create_table "attacks", force: :cascade do |t|
    t.integer "card_id", null: false
    t.string "name"
    t.string "cost"
    t.string "damage"
    t.text "effect"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_attacks_on_card_id"
  end

  create_table "cards", force: :cascade do |t|
    t.string "name"
    t.string "card_type"
    t.string "subtype"
    t.string "set_name"
    t.string "set_number"
    t.string "rarity"
    t.string "image_url"
    t.integer "hp"
    t.string "stage"
    t.string "type_symbol"
    t.integer "retreat_cost"
    t.string "artist"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "weakness"
    t.string "resistance"
    t.string "evolves_from"
    t.string "regulation_mark"
    t.string "set_full_name"
    t.decimal "price_usd", precision: 8, scale: 2
    t.decimal "price_eur", precision: 8, scale: 2
    t.text "effect"
    t.integer "pokemon_subtype_id"
    t.index ["pokemon_subtype_id"], name: "index_cards_on_pokemon_subtype_id"
  end

  create_table "collections", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "card_id", null: false
    t.integer "quantity"
    t.boolean "foil"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_collections_on_card_id"
    t.index ["user_id"], name: "index_collections_on_user_id"
  end

  create_table "deck_cards", force: :cascade do |t|
    t.integer "deck_id", null: false
    t.integer "card_id", null: false
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_deck_cards_on_card_id"
    t.index ["deck_id"], name: "index_deck_cards_on_deck_id"
  end

  create_table "deck_results", force: :cascade do |t|
    t.integer "deck_id", null: false
    t.string "result"
    t.string "opponent_deck_name"
    t.text "notes"
    t.datetime "played_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deck_id"], name: "index_deck_results_on_deck_id"
  end

  create_table "decks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_decks_on_user_id"
  end

  create_table "pokemon_subtypes", force: :cascade do |t|
    t.string "name"
    t.boolean "rule_box"
    t.integer "prize_cards_on_ko"
    t.text "rule_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "abilities", "cards"
  add_foreign_key "attacks", "cards"
  add_foreign_key "cards", "pokemon_subtypes"
  add_foreign_key "collections", "cards"
  add_foreign_key "collections", "users"
  add_foreign_key "deck_cards", "cards"
  add_foreign_key "deck_cards", "decks"
  add_foreign_key "deck_results", "decks"
  add_foreign_key "decks", "users"
end
