file_path = Rails.root.join("data_dictionary.json").to_s
if File.exist?(file_path)
  puts "Importing from #{file_path}..."
  Field.import_json(file_path)
  puts "Done. #{Field.count} fields now in the database."
else
  warn "Skipping import: #{file_path} not found."
end
