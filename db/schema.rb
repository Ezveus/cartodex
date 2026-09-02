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

ActiveRecord::Schema[8.1].define(version: 2026_09_02_155700) do
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
    t.string "name_normalized"
    t.integer "parent_id"
    t.integer "primary_card_id", null: false
    t.string "primary_fingerprint", null: false
    t.integer "secondary_card_id"
    t.string "secondary_fingerprint", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_archetypes_on_parent_id"
    t.index ["primary_fingerprint", "secondary_fingerprint"], name: "index_archetypes_on_fingerprint_pair", unique: true
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
    t.string "region", default: "international", null: false
    t.date "release_date"
    t.datetime "updated_at", null: false
    t.index ["region", "code"], name: "index_card_sets_on_region_and_code", unique: true
  end

  create_table "cards", force: :cascade do |t|
    t.string "artist"
    t.integer "card_set_id"
    t.string "card_type"
    t.string "cardmarket_url"
    t.datetime "created_at", null: false
    t.text "effect"
    t.string "evolves_from"
    t.string "fingerprint"
    t.integer "hp"
    t.string "image_url"
    t.string "name"
    t.string "name_normalized"
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
    t.index ["fingerprint"], name: "index_cards_on_fingerprint"
    t.index ["name", "fingerprint"], name: "index_cards_on_name_and_fingerprint"
    t.index ["pokemon_subtype_id"], name: "index_cards_on_pokemon_subtype_id"
    t.index ["set_name", "set_number"], name: "index_cards_on_set_name_and_set_number", unique: true
  end

  create_table "collections", force: :cascade do |t|
    t.integer "card_id", null: false
    t.datetime "created_at", null: false
    t.string "finish", default: "unknown", null: false
    t.string "language", default: "unknown", null: false
    t.integer "quantity"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["card_id"], name: "index_collections_on_card_id"
    t.index ["user_id", "card_id", "language", "finish"], name: "index_collections_on_user_card_and_variant", unique: true
    t.index ["user_id"], name: "index_collections_on_user_id"
  end

  create_table "deck_cards", force: :cascade do |t|
    t.integer "card_id", null: false
    t.datetime "created_at", null: false
    t.integer "deck_id", null: false
    t.integer "owned_copies", default: 0, null: false
    t.integer "quantity"
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_deck_cards_on_card_id"
    t.index ["deck_id", "card_id"], name: "index_deck_cards_on_deck_id_and_card_id", unique: true
    t.index ["deck_id"], name: "index_deck_cards_on_deck_id"
  end

  create_table "deck_results", force: :cascade do |t|
    t.integer "archetype_id"
    t.datetime "created_at", null: false
    t.integer "deck_id", null: false
    t.string "match_format", default: "bo1", null: false
    t.text "notes"
    t.datetime "played_at"
    t.string "result"
    t.string "score"
    t.integer "tournament_id"
    t.datetime "updated_at", null: false
    t.index ["archetype_id"], name: "index_deck_results_on_archetype_id"
    t.index ["deck_id"], name: "index_deck_results_on_deck_id"
    t.index ["tournament_id"], name: "index_deck_results_on_tournament_id"
  end

  create_table "decks", force: :cascade do |t|
    t.integer "archetype_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "format", default: "standard", null: false
    t.string "key", null: false
    t.string "name"
    t.string "name_normalized"
    t.string "other_format_name"
    t.boolean "physical", default: false, null: false
    t.integer "standard_pool_id"
    t.boolean "tcg_live", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["archetype_id"], name: "index_decks_on_archetype_id"
    t.index ["key"], name: "index_decks_on_key", unique: true
    t.index ["standard_pool_id"], name: "index_decks_on_standard_pool_id"
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

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.integer "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.integer "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "pokemon_subtypes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "prize_cards_on_ko"
    t.boolean "rule_box"
    t.text "rule_text"
    t.datetime "updated_at", null: false
  end

  create_table "standard_pools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "first_card_set_id", null: false
    t.integer "last_card_set_id", null: false
    t.date "legal_on", null: false
    t.json "regulation_marks", null: false
    t.date "released_on", null: false
    t.datetime "updated_at", null: false
    t.index ["first_card_set_id", "last_card_set_id"], name: "index_standard_pools_on_bounds", unique: true
    t.index ["first_card_set_id"], name: "index_standard_pools_on_first_card_set_id"
    t.index ["last_card_set_id"], name: "index_standard_pools_on_last_card_set_id"
  end

  create_table "tournament_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date_of_birth", null: false
    t.string "player_id", null: false
    t.string "player_name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["player_id"], name: "index_tournament_profiles_on_player_id", unique: true
    t.index ["user_id"], name: "index_tournament_profiles_on_user_id"
  end

  create_table "tournaments", force: :cascade do |t|
    t.integer "championship_points"
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "deck_id", null: false
    t.string "format", default: "standard", null: false
    t.string "name", null: false
    t.string "name_normalized"
    t.string "other_format_name"
    t.integer "participant_count"
    t.integer "placement"
    t.integer "standard_pool_id"
    t.string "tier", default: "regional", null: false
    t.integer "tournament_profile_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["deck_id"], name: "index_tournaments_on_deck_id"
    t.index ["standard_pool_id"], name: "index_tournaments_on_standard_pool_id"
    t.index ["tournament_profile_id"], name: "index_tournaments_on_tournament_profile_id"
    t.index ["user_id"], name: "index_tournaments_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "api_token_created_at"
    t.string "api_token_digest"
    t.datetime "api_token_expires_at"
    t.datetime "api_token_last_used_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["api_token_digest"], name: "index_users_on_api_token_digest", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "abilities", "cards"
  add_foreign_key "archetypes", "archetypes", column: "parent_id"
  add_foreign_key "archetypes", "cards", column: "primary_card_id"
  add_foreign_key "archetypes", "cards", column: "secondary_card_id"
  add_foreign_key "attacks", "cards"
  add_foreign_key "cards", "card_sets"
  add_foreign_key "cards", "pokemon_subtypes"
  add_foreign_key "collections", "cards"
  add_foreign_key "collections", "users"
  add_foreign_key "deck_cards", "cards"
  add_foreign_key "deck_cards", "decks"
  add_foreign_key "deck_results", "archetypes"
  add_foreign_key "deck_results", "decks"
  add_foreign_key "deck_results", "tournaments"
  add_foreign_key "decks", "archetypes"
  add_foreign_key "decks", "standard_pools"
  add_foreign_key "decks", "users"
  add_foreign_key "imports", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "standard_pools", "card_sets", column: "first_card_set_id"
  add_foreign_key "standard_pools", "card_sets", column: "last_card_set_id"
  add_foreign_key "tournament_profiles", "users"
  add_foreign_key "tournaments", "decks"
  add_foreign_key "tournaments", "standard_pools"
  add_foreign_key "tournaments", "tournament_profiles"
  add_foreign_key "tournaments", "users"
end
