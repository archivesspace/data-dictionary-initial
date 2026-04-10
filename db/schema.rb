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

ActiveRecord::Schema[8.1].define(version: 2026_03_28_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
