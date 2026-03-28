namespace :import do
  desc "Import fields from data_dictionary.json (default path: Rails.root/data_dictionary.json)"
  task :json, [:file] => :environment do |_, args|
    file_path = args[:file] || Rails.root.join("data_dictionary.json").to_s

    unless File.exist?(file_path)
      abort "File not found: #{file_path}"
    end

    puts "Importing from #{file_path}..."
    Field.import_json(file_path)
    puts "Done. #{Field.count} fields now in the database."
  end

  desc "Wipe all fields and search index, then reimport from data_dictionary.json (default path: Rails.root/data_dictionary.json)"
  task :reset, [:file] => :environment do |_, args|
    file_path = args[:file] || Rails.root.join("data_dictionary.json").to_s

    unless File.exist?(file_path)
      abort "File not found: #{file_path}"
    end

    puts "Deleting all fields and search index..."
    PgSearch::Document.delete_all
    Field.delete_all
    puts "Importing from #{file_path}..."
    Field.import_json(file_path)
    puts "Done. #{Field.count} fields now in the database."
  end
end
