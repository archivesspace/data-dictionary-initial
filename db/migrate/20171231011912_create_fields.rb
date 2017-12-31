class CreateFields < ActiveRecord::Migration[5.1]
  def change
    create_table :fields do |t|
      t.string :field_id
      t.string :field_name
      t.string :field_type
      t.string :field_table
      t.text :description
      t.string :staff_interface_label
      t.string :public_interface_label
      t.boolean :system_required
      t.boolean :system_generated
      t.text :example_data

      t.timestamps
    end
  end
end
