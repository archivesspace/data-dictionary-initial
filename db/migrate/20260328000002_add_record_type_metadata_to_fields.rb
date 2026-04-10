class AddRecordTypeMetadataToFields < ActiveRecord::Migration[8.1]
  def change
    # Record-type-level description (separate from the per-field :description column)
    add_column :fields, :record_type_description, :text

    # Which abstract schema this record type inherits from, e.g. "abstract_agent"
    add_column :fields, :parent_schema, :string

    # JSON arrays of relationship, subrecord, and type-constraint metadata
    add_column :fields, :relationships,         :text
    add_column :fields, :subrecords,            :text
    add_column :fields, :allowed_type_values,   :text
    add_column :fields, :used_on,               :text

    # Human-readable summary of fields inherited from a parent schema
    add_column :fields, :inherited_fields, :text
  end
end
