class AddJsonFieldsToFields < ActiveRecord::Migration[8.1]
  def change
    add_column :fields, :api_endpoint, :string
    add_column :fields, :conditions, :text
    add_column :fields, :default_value, :text
    add_column :fields, :dynamic_enum, :string
    add_column :fields, :enum_values, :text
    add_column :fields, :export_mappings, :text
    add_column :fields, :items, :string
    add_column :fields, :max_length, :integer
    add_column :fields, :min_items, :integer
    add_column :fields, :pattern, :string
    add_column :fields, :refs, :text
    add_column :fields, :required_permission, :string
    add_column :fields, :scope, :string
    add_column :fields, :solr_field, :string
    add_column :fields, :solr_index, :string
    add_column :fields, :solr_note, :text
    add_column :fields, :ui_display, :text
    add_column :fields, :ui_visibility, :string
    add_column :fields, :version_note, :text
  end
end
