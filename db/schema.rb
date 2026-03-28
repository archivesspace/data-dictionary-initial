# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_28_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "fields", force: :cascade do |t|
    t.text "allowed_type_values"
    t.string "api_endpoint"
    t.text "conditions"
    t.datetime "created_at", null: false
    t.text "default_value"
    t.text "description"
    t.string "dynamic_enum"
    t.text "enum_values"
    t.text "example_data"
    t.text "export_mappings"
    t.string "field_id"
    t.string "field_name"
    t.string "field_table"
    t.string "field_type"
    t.text "inherited_fields"
    t.string "items"
    t.integer "max_length"
    t.integer "min_items"
    t.string "parent_schema"
    t.string "pattern"
    t.string "public_interface_label"
    t.text "record_type_description"
    t.text "refs"
    t.text "relationships"
    t.string "required_permission"
    t.string "scope"
    t.string "solr_field"
    t.string "solr_index"
    t.text "solr_note"
    t.string "staff_interface_label"
    t.text "subrecords"
    t.boolean "system_generated"
    t.boolean "system_required"
    t.text "ui_display"
    t.string "ui_visibility"
    t.datetime "updated_at", null: false
    t.text "used_on"
    t.text "version_note"
  end

  create_table "pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "searchable_id"
    t.string "searchable_type"
    t.datetime "updated_at", null: false
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable_type_and_searchable_id"
  end
end
