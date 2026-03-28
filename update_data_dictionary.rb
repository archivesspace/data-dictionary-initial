#!/usr/bin/env ruby --disable-gems
# Usage:
#   ruby --disable-gems scripts/update_data_dictionary.rb <new_dictionary.json>
#   ruby --disable-gems scripts/update_data_dictionary.rb <new_dictionary.json> --dry-run
#   ruby --disable-gems scripts/update_data_dictionary.rb <new_dictionary.json> --output path/to/other.json
#
# Compares a new data dictionary JSON against the current one, prints a changelog,
# and updates data_dictionary.json in place (unless --dry-run is given).
#
# The --disable-gems flag avoids conflicts with bundled gem versions in this repo.

require 'json'
require 'time'
require 'optparse'

# ---------------------------------------------------------------------------
# Canonical field properties and their human-readable display labels.
# These are the expected keys in every field/subrecord/relationship entry.
# ---------------------------------------------------------------------------
FIELD_DISPLAY_NAMES = {
  'name'                => 'Field Name',
  'type'                => 'Field Type',
  'description'         => 'Description',
  'staff_label'         => 'Staff Interface Label',
  'public_label'        => 'Public Interface Label',
  'required'            => 'System required?',
  'readonly'            => 'System generated?',
  'example'             => 'Example Data',
  'default'             => 'Default Value',
  'enum'                => 'Allowed Values',
  'dynamic_enum'        => 'Dynamic Enumeration',
  'conditions'          => 'Conditional Rules',
  'pattern'             => 'Value Pattern',
  'max_length'          => 'Maximum Length',
  'min_items'           => 'Minimum Items',
  'items'               => 'Array Item Type',
  'refs'                => 'Referenced Record Types',
  'required_permission' => 'Required Permission',
  'export_mappings'     => 'Export Mappings',
  'solr_field'          => 'Solr Field',
  'solr_index'          => 'Solr Index Strategy',
  'solr_note'           => 'Solr Note',
  'version_note'        => 'Version Note'
}.freeze

REPO_ROOT = File.expand_path('..', __dir__)
DEFAULT_DICT_PATH = File.join(REPO_ROOT, 'data_dictionary.json')

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
options = { dry_run: false, output: DEFAULT_DICT_PATH }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: update_data_dictionary.rb NEW_DICT.json [options]"
  opts.on('--dry-run', 'Print changelog but do not write changes') { options[:dry_run] = true }
  opts.on('--output PATH', 'Write updated dictionary to PATH instead of default') { |p| options[:output] = p }
end
parser.parse!

if ARGV.empty?
  puts parser.banner
  exit 1
end

new_path = ARGV[0]
unless File.exist?(new_path)
  abort "ERROR: File not found: #{new_path}"
end
unless File.exist?(DEFAULT_DICT_PATH)
  abort "ERROR: Current dictionary not found at #{DEFAULT_DICT_PATH}"
end

# ---------------------------------------------------------------------------
# Load both files
# ---------------------------------------------------------------------------
current = JSON.parse(File.read(DEFAULT_DICT_PATH))
incoming = JSON.parse(File.read(new_path))

# ---------------------------------------------------------------------------
# Deep diff helpers
# ---------------------------------------------------------------------------

# Returns a flat list of change hashes describing every difference found.
# Each change: { path: String, change: :added|:removed|:modified, from: val, to: val }
def deep_diff(path, old_val, new_val, changes = [])
  if old_val.class != new_val.class
    changes << { path: path, change: :modified, from: old_val, to: new_val }
    return changes
  end

  case old_val
  when Hash
    (old_val.keys | new_val.keys).each do |k|
      child_path = path.empty? ? k.to_s : "#{path}.#{k}"
      if !old_val.key?(k)
        changes << { path: child_path, change: :added, from: nil, to: new_val[k] }
      elsif !new_val.key?(k)
        changes << { path: child_path, change: :removed, from: old_val[k], to: nil }
      else
        deep_diff(child_path, old_val[k], new_val[k], changes)
      end
    end
  when Array
    # For arrays we do element-by-element comparison.
    # If elements are hashes with a "name" key, match by name for better diffs.
    if old_val.all? { |e| e.is_a?(Hash) && e['name'] } &&
       new_val.all? { |e| e.is_a?(Hash) && e['name'] }
      old_by_name = old_val.each_with_object({}) { |e, h| h[e['name']] = e }
      new_by_name = new_val.each_with_object({}) { |e, h| h[e['name']] = e }
      (old_by_name.keys | new_by_name.keys).each do |name|
        child_path = "#{path}[name=#{name}]"
        if !old_by_name.key?(name)
          changes << { path: child_path, change: :added, from: nil, to: new_by_name[name] }
        elsif !new_by_name.key?(name)
          changes << { path: child_path, change: :removed, from: old_by_name[name], to: nil }
        else
          deep_diff(child_path, old_by_name[name], new_by_name[name], changes)
        end
      end
    elsif old_val != new_val
      changes << { path: path, change: :modified, from: old_val, to: new_val }
    end
  else
    changes << { path: path, change: :modified, from: old_val, to: new_val } if old_val != new_val
  end

  changes
end

# ---------------------------------------------------------------------------
# Run the comparison
# ---------------------------------------------------------------------------

# Sections whose entries are diffed individually (key-by-key) and labelled by
# section name in the changelog.
DIFFED_SECTIONS = %w[record_types subrecord_types note_types enumerations record_examples].freeze

all_changes = []

DIFFED_SECTIONS.each do |section|
  old_section = current[section] || {}
  new_section = incoming[section] || {}

  (old_section.keys | new_section.keys).each do |key|
    if !old_section.key?(key)
      all_changes << { section: section, path: "#{section}.#{key}", change: :added, from: nil, to: new_section[key] }
    elsif !new_section.key?(key)
      all_changes << { section: section, path: "#{section}.#{key}", change: :removed, from: old_section[key], to: nil }
    else
      sub_changes = deep_diff('', old_section[key], new_section[key])
      sub_changes.each do |c|
        c[:section] = section
        c[:path] = "#{section}.#{key}#{c[:path].empty? ? '' : ".#{c[:path]}"}"
      end
      all_changes.concat(sub_changes)
    end
  end
end

# Diff remaining top-level keys (metadata, changelog, etc.)
ignored = DIFFED_SECTIONS + ['changelog']
meta_changes = deep_diff('', current.reject { |k, _| ignored.include?(k) },
                              incoming.reject { |k, _| ignored.include?(k) })
meta_changes.each { |c| c[:section] = 'metadata' }
all_changes.concat(meta_changes)

# ---------------------------------------------------------------------------
# Format and print changelog
# ---------------------------------------------------------------------------
ICONS = { added: '+', removed: '-', modified: '~' }
COLORS = { added: "\e[32m", removed: "\e[31m", modified: "\e[33m", reset: "\e[0m" }

def colorize(text, type)
  "#{COLORS[type]}#{text}#{COLORS[:reset]}"
end

def summarize(val)
  return 'nil' if val.nil?
  return val.inspect if val.is_a?(String) || val == true || val == false || val.is_a?(Integer)
  return "{...}" if val.is_a?(Hash)
  return "[...]" if val.is_a?(Array)
  val.inspect
end

# Returns the human-readable label for a field property key, falling back to the raw key.
def display_label(key)
  FIELD_DISPLAY_NAMES[key.to_s] || key.to_s
end

# Formats a field entry hash as a multi-line block of canonical property lines.
def format_field_entry(entry)
  return summarize(entry) unless entry.is_a?(Hash)
  lines = FIELD_DISPLAY_NAMES.keys.filter_map do |key|
    next unless entry.key?(key)
    "        #{display_label(key)}: #{summarize(entry[key])}"
  end
  # Include any extra keys not in the canonical list
  extra = entry.keys - FIELD_DISPLAY_NAMES.keys
  extra.each { |k| lines << "        #{k}: #{summarize(entry[k])}" }
  "\n" + lines.join("\n")
end

puts
puts "=" * 70
puts "  DATA DICTIONARY DIFF"
puts "  Current: #{DEFAULT_DICT_PATH}"
puts "  Incoming: #{new_path}"
puts "  Generated: #{Time.now.iso8601}"
puts "=" * 70

if all_changes.empty?
  puts "\n  No differences found. Data dictionary is up to date.\n\n"
else
  by_section = all_changes.group_by { |c| c[:section] }
  by_section.each do |section, changes|
    puts "\n  [#{section}]"
    changes.each do |c|
      icon = ICONS[c[:change]]
      # Translate the last path segment to a human-readable label if it matches a canonical field property.
      display_path = c[:path].gsub(/\.([^.\[]+)$/) { ".#{display_label($1)}" }
      line = "    #{icon} #{display_path}"
      case c[:change]
      when :added
        val = c[:to].is_a?(Hash) ? format_field_entry(c[:to]) : " => #{summarize(c[:to])}"
        line += val
      when :removed
        val = c[:from].is_a?(Hash) ? format_field_entry(c[:from]) : " (was: #{summarize(c[:from])})"
        line += val
      when :modified
        line += ": #{summarize(c[:from])} => #{summarize(c[:to])}"
      end
      puts colorize(line, c[:change])
    end
  end

  added   = all_changes.count { |c| c[:change] == :added }
  removed = all_changes.count { |c| c[:change] == :removed }
  modified = all_changes.count { |c| c[:change] == :modified }

  puts
  puts "  Summary: #{colorize("+#{added} added", :added)}  " \
       "#{colorize("-#{removed} removed", :removed)}  " \
       "#{colorize("~#{modified} modified", :modified)}"
  puts
end

# ---------------------------------------------------------------------------
# Build the updated dictionary
# ---------------------------------------------------------------------------
# For each diffed section: keep current entries as base, apply incoming on top.
# New entries from incoming are added; existing ones are replaced by incoming;
# entries only in current are preserved.
#
# Exception — record_examples: current wins over incoming because the generator
# always produces an empty record_examples section, and examples are hand-authored.
updated = current.dup

%w[record_types subrecord_types note_types enumerations].each do |section|
  old_section = current[section] || {}
  new_section = incoming[section] || {}
  updated[section] = old_section.merge(new_section)
end

# record_examples: preserve hand-authored current content; only add truly new
# keys from incoming (generator output is always empty here).
old_examples = current['record_examples'] || {}
new_examples = incoming['record_examples'] || {}
updated['record_examples'] = new_examples.merge(old_examples)

# Update metadata timestamps
updated['metadata'] ||= {}
updated['metadata']['last_updated'] = Time.now.iso8601
updated['metadata']['previous_update'] = current.dig('metadata', 'last_updated')

# Append a changelog entry to the file
updated['changelog'] ||= []
if all_changes.any?
  updated['changelog'].unshift({
    'timestamp'  => Time.now.iso8601,
    'source'     => new_path,
    'added'      => all_changes.select { |c| c[:change] == :added }.map { |c| c[:path] },
    'removed'    => all_changes.select { |c| c[:change] == :removed }.map { |c| c[:path] },
    'modified'   => all_changes.select { |c| c[:change] == :modified }.map { |c| c[:path] }
  })
end

# ---------------------------------------------------------------------------
# Write or dry-run
# ---------------------------------------------------------------------------
if options[:dry_run]
  puts "  --dry-run: no changes written.\n\n"
else
  File.write(options[:output], JSON.pretty_generate(updated))
  puts "  Updated: #{options[:output]}\n\n"
end
