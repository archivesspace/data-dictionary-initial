class Field < ApplicationRecord
  include PgSearch
  pg_search_scope :search_by_keyword, :against => [:field_id, :field_name, :field_type, :field_table, :description, :staff_interface_label, :public_interface_label]
  pg_search_scope :search_by_field_name, :against => :field_name
  pg_search_scope :search_by_table, :against => :field_table


  def self.import(file)
    spreadsheet = open_spreadsheet(file)
    spreadsheet.sheets.each do |s|
      spreadsheet.default_sheet = s
      next if !spreadsheet.first_row
      header = spreadsheet.row(1)

      header.map! do |item|
        break if item.nil? || item.empty?
        item.downcase.parameterize(separator: '_')
      end
      header.push("field_table")
      header.push("field_id")

      (2..spreadsheet.last_row).each do |i|
        next_row = spreadsheet.row(i)
        break if next_row[0].nil? || next_row[0].empty?
        next_row.push(s)
        next_row.push("#{next_row[0]}-#{s}")
        row = Hash[[header, next_row].transpose]
        if row["system_required"] != nil && row["system_required"] =~ /^Required$/i
          row["system_required"] = true
        else
          row["system_required"] = false
        end
        if row["system_generated"] != nil && row["system_generated"] =~ /^The contents of this field are automatically generated by the application\.$/i
          row["system_generated"] = true
        else
          row["system_generated"] = false
        end
        row["field_type"].gsub!(/,/,'') if row["field_type"] != nil
        field = find_by(field_id: row["field_id"]) || new
        field.attributes = row.to_hash
        field.save!
      end
    end
  end

  def self.open_spreadsheet(file)
    case File.extname(file.original_filename)
    when ".csv" then Roo::Csv.new(file.path)
    when ".xls" then Roo::Excel.new(file.path)
    when ".xlsx" then Roo::Excelx.new(file.path)
    else raise "Unknown file type: #{file.original_filename}"
    end
  end

  def self.like(field_name)
    field_name.nil? ? [] : where(['field_name LIKE ?', "%#{field_name}%"])
  end

  def self.rebuild_pg_search_documents
    find_each { |record| record.update_pg_search_document }
  end


end
