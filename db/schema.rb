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

ActiveRecord::Schema[8.1].define(version: 2026_04_11_151349) do
  create_table "abilities", force: :cascade do |t|
    t.integer "card_id", null: false
    t.datetime "created_at", null: false
    t.text "effect"
    t.string "name"
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_abilities_on_card_id"
  end

  create_table "archetypes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "parent_id"
    t.integer "primary_pokemon_id", null: false
    t.integer "secondary_pokemon_id"
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_archetypes_on_parent_id"
    t.index ["primary_pokemon_id", "secondary_pokemon_id"], name: "idx_on_primary_pokemon_id_secondary_pokemon_id_2a04cf9ccd", unique: true
  end

  create_table "attacks", force: :cascade do |t|
    t.integer "card_id", null: false
    t.string "cost"
    t.datetime "created_at", null: false
    t.string "damage"
    t.text "effect"
    t.string "name"
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_attacks_on_card_id"
  end

  create_table "card_sets", force: :cascade do |t|
    t.string "block_name"
    t.string "code"
    t.datetime "created_at", null: false
    t.string "logo_url"
    t.string "name"
    t.date "release_date"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_card_sets_on_code", unique: true
  end

  create_table "cards", force: :cascade do |t|
    t.string "artist"
    t.integer "card_set_id"
    t.string "card_type"
    t.datetime "created_at", null: false
    t.text "effect"
    t.string "evolves_from"
    t.string "fingerprint"
    t.integer "hp"
    t.string "image_url"
    t.string "name"
    t.integer "pokemon_subtype_id"
    t.decimal "price_eur", precision: 8, scale: 2
    t.decimal "price_usd", precision: 8, scale: 2
    t.string "rarity"
    t.string "regulation_mark"
    t.string "resistance"
    t.integer "retreat_cost"
    t.string "set_full_name"
    t.string "set_name"
    t.string "set_number"
    t.string "stage"
    t.string "subtype"
    t.string "type_symbol"
    t.datetime "updated_at", null: false
    t.string "weakness"
    t.index ["card_set_id"], name: "index_cards_on_card_set_id"
    t.index ["name", "fingerprint"], name: "index_cards_on_name_and_fingerprint"
    t.index ["pokemon_subtype_id"], name: "index_cards_on_pokemon_subtype_id"
  end

  create_table "collections", force: :cascade do |t|
    t.integer "card_id", null: false
    t.datetime "created_at", null: false
    t.boolean "foil"
    t.integer "quantity"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["card_id"], name: "index_collections_on_card_id"
    t.index ["user_id"], name: "index_collections_on_user_id"
  end

  create_table "deck_cards", force: :cascade do |t|
    t.integer "card_id", null: false
    t.datetime "created_at", null: false
    t.integer "deck_id", null: false
    t.integer "quantity"
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_deck_cards_on_card_id"
    t.index ["deck_id"], name: "index_deck_cards_on_deck_id"
  end

  create_table "deck_results", force: :cascade do |t|
    t.integer "archetype_id"
    t.datetime "created_at", null: false
    t.integer "deck_id", null: false
    t.text "notes"
    t.datetime "played_at"
    t.string "result"
    t.datetime "updated_at", null: false
    t.index ["archetype_id"], name: "index_deck_results_on_archetype_id"
    t.index ["deck_id"], name: "index_deck_results_on_deck_id"
  end

  create_table "decks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_decks_on_user_id"
  end

  create_table "imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "kind", null: false
    t.string "label", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["kind", "status"], name: "index_imports_on_kind_and_status"
    t.index ["user_id", "status"], name: "index_imports_on_user_id_and_status"
    t.index ["user_id"], name: "index_imports_on_user_id"
  end

  create_table "pokemon_subtypes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "prize_cards_on_ko"
    t.boolean "rule_box"
    t.text "rule_text"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "abilities", "cards"
  add_foreign_key "archetypes", "archetypes", column: "parent_id"
  add_foreign_key "archetypes", "cards", column: "primary_pokemon_id"
  add_foreign_key "archetypes", "cards", column: "secondary_pokemon_id"
  add_foreign_key "attacks", "cards"
  add_foreign_key "cards", "card_sets"
  add_foreign_key "cards", "pokemon_subtypes"
  add_foreign_key "collections", "cards"
  add_foreign_key "collections", "users"
  add_foreign_key "deck_cards", "cards"
  add_foreign_key "deck_cards", "decks"
  add_foreign_key "deck_results", "archetypes"
  add_foreign_key "deck_results", "decks"
  add_foreign_key "decks", "users"
  add_foreign_key "imports", "users"
end
