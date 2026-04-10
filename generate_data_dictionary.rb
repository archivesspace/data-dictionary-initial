#!/usr/bin/env ruby --disable-gems
# Generates data_dictionary.json from scratch by reading ArchivesSpace source files.
#
# Sources read:
#   common/schemas/*.rb             - field names, types, constraints, enum refs
#   common/locales/en.yml           - staff interface field labels (shared/backend)
#   frontend/config/locales/en.yml  - staff interface field labels (frontend-specific)
#   public/config/locales/en.yml    - public interface field labels
#   common/db/migrations/*.rb       - enumeration value definitions
#
# Fields that require manual enrichment are written as null placeholders:
#   description, example, export_mappings, solr_field, solr_index,
#   solr_note, conditions, required_permission, version_note
#
# Usage:
#   ruby --disable-gems scripts/generate_data_dictionary.rb [options]
#
# Options:
#   --output PATH    Write to PATH instead of data_dictionary.json
#   --dry-run        Print summary without writing any file
#   --force          Overwrite output file without prompting

require 'json'
require 'yaml'
require 'date'
require 'optparse'

REPO_ROOT = File.expand_path('..', __dir__)
DEFAULT_OUTPUT = File.join(REPO_ROOT, 'data_dictionary.json')

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
DEFAULT_DEMO_DB = File.join(REPO_ROOT, 'build/mysql_db_fixtures/demo.sql.gz')

options = { dry_run: false, output: DEFAULT_OUTPUT, force: false, demo_db: DEFAULT_DEMO_DB, preserve_enrichments: true }
OptionParser.new do |opts|
  opts.banner = "Usage: generate_data_dictionary.rb [options]"
  opts.on('--output PATH', 'Write to PATH instead of data_dictionary.json') { |p| options[:output] = p }
  opts.on('--dry-run', 'Print summary without writing') { options[:dry_run] = true }
  opts.on('--force', 'Overwrite existing file without prompting') { options[:force] = true }
  opts.on('--demo-db PATH', 'Path to demo.sql.gz for example values (default: build/mysql_db_fixtures/demo.sql.gz)') { |p| options[:demo_db] = p }
  opts.on('--no-examples', 'Skip example extraction from demo database') { options[:demo_db] = nil }
  opts.on('--no-preserve-enrichments', 'Do not carry forward manual enrichments from existing output file') { options[:preserve_enrichments] = false }
end.parse!

# ---------------------------------------------------------------------------
# Step 1: Parse enumerations from all migration files
#
# Handles both single-line and multi-line create_enum / create_editable_enum calls:
#   create_enum("name", ["val1", "val2"])
#   create_editable_enum('name', ["val1",
#                                  "val2"])
# ---------------------------------------------------------------------------
def parse_enumerations(migrations_dir)
  enums = {}
  Dir.glob(File.join(migrations_dir, '*.rb')).sort.each do |path|
    # Collapse the file to a single line so multi-line arrays are captured
    content = File.read(path).gsub(/\s+/, ' ')
    content.scan(/create_(?:editable_)?enum\s*\(\s*['"]([^'"]+)['"]\s*,\s*\[([^\]]*)\]/) do |name, values_str|
      values = values_str.scan(/['"]([^'"]+)['"]/).flatten
      enums[name] = values unless values.empty?
    end
  end
  enums
end

# ---------------------------------------------------------------------------
# Step 2: Load YAML locale files and flatten each into a nested Ruby hash
#
# The YAML files use anchors/aliases (&name / <<: *name) which YAML.load
# resolves automatically. We read three sources:
#   :common   - common/locales/en.yml         (shared staff labels)
#   :frontend - frontend/config/locales/en.yml (staff-only labels)
#   :public   - public/config/locales/en.yml   (public interface labels)
# ---------------------------------------------------------------------------
def load_locales(repo_root)
  sources = {
    common:   'common/locales/en.yml',
    frontend: 'frontend/config/locales/en.yml',
    public:   'public/config/locales/en.yml',
  }
  sources.transform_values do |rel_path|
    abs = File.join(repo_root, rel_path)
    next {} unless File.exist?(abs)
    begin
      # aliases: true allows YAML anchors; falls back for older Ruby versions
      loaded = YAML.load_file(abs, aliases: true) rescue YAML.load_file(abs)
      (loaded.is_a?(Hash) && loaded['en']) ? loaded['en'] : {}
    rescue => e
      warn "  WARN: Could not load locale #{rel_path}: #{e.message}"
      {}
    end
  end
end

# Look up the label string for a specific field within a record type section.
# Searches the given locale hashes in order and returns the first string match.
# Skips values that are hashes (sub-sections) or tooltip/help strings.
def lookup_label(locale_list, record_type, field_name)
  locale_list.each do |locale|
    section = locale[record_type]
    next unless section.is_a?(Hash)
    val = section[field_name]
    return val if val.is_a?(String) && !val.strip.empty? && !val.include?('<p>')
  end
  nil
end

# ---------------------------------------------------------------------------
# Step 3: Evaluate schema files
#
# Each schema file is a self-contained Ruby hash literal of the form:
#   { :schema => { "$schema" => "...", "properties" => { ... } } }
# We eval it directly since the files contain no executable side-effects.
# ---------------------------------------------------------------------------
def load_schema(path)
  # Suppress Ruby warnings during eval: schema files contain known patterns
  # (duplicate hash keys, constant redefinitions) that produce noise but do
  # not affect the values we extract.
  old_verbose = $VERBOSE
  $VERBOSE = nil
  eval(File.read(path)) # rubocop:disable Security/Eval
rescue => e
  warn "  WARN: Could not parse #{File.basename(path)}: #{e.message}"
  nil
ensure
  $VERBOSE = old_verbose
end

# ---------------------------------------------------------------------------
# Step 3b: Scope and inherited-fields helpers
# ---------------------------------------------------------------------------

# Derive the scope of a record type from its URI.
# Returns "repository" (scoped per repository), "global", or nil (no URI).
def derive_scope(uri)
  return nil unless uri.is_a?(String)
  uri.include?(':repo_id') ? 'repository' : 'global'
end

# Scope descriptions for FORCE_RECORD_TYPES that have no URI.
EMBEDDED_RECORD_SCOPES = {
  'date'             => 'global (embedded in archival records)',
  'extent'           => 'global (embedded in archival records)',
  'file_version'     => 'global (embedded in digital objects)',
  'instance'         => 'global (embedded in archival records)',
  'rights_statement' => 'global (embedded in archival records)',
}.freeze

# Build an inherited_fields note: a human-readable string listing the parent
# schema's properties that are NOT overridden in the child schema.
# Returns nil when there is no parent or all parent fields are overridden.
def build_inherited_fields_note(name, raw_schemas)
  raw = raw_schemas[name]
  return nil unless raw

  schema      = raw[:schema]
  parent_name = schema['parent']
  return nil unless parent_name.is_a?(String) && !parent_name.empty?

  parent_raw = raw_schemas[parent_name]
  return nil unless parent_raw

  parent_props = parent_raw[:schema]['properties'] || {}
  own_props    = schema['properties'] || {}

  inherited = parent_props.keys.reject { |k| own_props.key?(k) || k.start_with?('_') }
  return nil if inherited.empty?

  "See #{parent_name} for: #{inherited.join(', ')}"
end

# ---------------------------------------------------------------------------
# Step 3c: Field classification helpers
#
# Each property in a schema belongs to one of three categories:
#   :field        - scalar/primitive property (string, boolean, integer, date, enum)
#   :subrecord    - embedded sub-record (type is a JSONModel object reference)
#   :relationship - cross-record link (uses subtype:ref / contains a ref pointer)
#
# The distinction matters for output: simple fields go in "fields", embedded
# JSONModel sub-records go in "subrecords", and ref links go in "relationships".
# ---------------------------------------------------------------------------

# Extract the target JSONModel schema name(s) from a type value.
# Returns an Array of schema name strings.
def extract_jsonmodel_ref_names(type_val)
  case type_val
  when String
    m = type_val.match(/JSONModel\(:([^)]+)\)/)
    m ? [m[1]] : []
  when Array
    type_val.flat_map { |t|
      s = t.is_a?(Hash) ? t['type'].to_s : t.to_s
      m = s.match(/JSONModel\(:([^)]+)\)/)
      m ? [m[1]] : []
    }.uniq
  else
    []
  end
end

# Classify a single property hash into :field, :subrecord, or :relationship.
def classify_field(prop, raw_schemas)
  # Direct subtype:ref on the property itself (non-array ref object)
  return :relationship if prop['subtype'] == 'ref'

  items = prop['items']

  if items.is_a?(Hash)
    # Array items that are a direct subtype:ref inline object
    return :relationship if items['subtype'] == 'ref'

    # Array items that reference JSONModel schemas — check if those schemas are
    # themselves subtype:ref (e.g. accession_parts_relationship)
    names = extract_jsonmodel_ref_names(items['type'])
    names.each do |schema_name|
      ref_schema = raw_schemas[schema_name]
      return :relationship if ref_schema&.dig(:schema, 'subtype') == 'ref'
    end

    # At least one item is a JSONModel object reference → subrecord
    return :subrecord unless names.empty?
  end

  # Single JSONModel object reference (non-array)
  type = prop['type']
  return :subrecord if type.is_a?(String) && type.match?(/JSONModel\(:.*\) object/)

  :field
end

# Build a subrecords-section entry for a JSONModel-embedded field.
def build_subrecord_entry(field_name, prop)
  array_type = prop['type'] == 'array'
  items_def  = prop['items']

  # Resolve the sub-record schema name(s)
  names =
    if array_type && items_def.is_a?(Hash)
      extract_jsonmodel_ref_names(items_def['type'])
    else
      extract_jsonmodel_ref_names(prop['type'])
    end

  items_val = names.length == 1 ? names.first : names.empty? ? nil : names

  entry = {
    'name'        => field_name,
    'type'        => array_type ? 'array' : 'object',
    'items'       => items_val,
    'description' => nil
  }
  entry['readonly']  = true if prop['readonly'] == true || prop['readonly'] == 'true'
  entry['required']  = true if prop['ifmissing'] == 'error'
  entry['min_items'] = prop['minItems'] if prop['minItems']
  entry
end

# Build a relationships-section entry for a subtype:ref field.
def build_relationship_entry(field_name, prop, raw_schemas)
  array_type = prop['type'] == 'array'

  # Collect the target record type(s) by following the ref pointer(s)
  refs = []

  collect_refs = lambda do |node|
    return unless node.is_a?(Hash)
    if node['subtype'] == 'ref' && node['properties']
      ref_prop = node['properties']['ref']
      refs.concat(extract_jsonmodel_ref_names(ref_prop['type'])) if ref_prop
    end
    # Union of JSONModel schemas: look up each to get their own ref targets
    names = extract_jsonmodel_ref_names(node['type'])
    names.each do |schema_name|
      ref_schema = raw_schemas[schema_name]
      next unless ref_schema&.dig(:schema, 'subtype') == 'ref'
      ref_prop = ref_schema.dig(:schema, 'properties', 'ref')
      refs.concat(extract_jsonmodel_ref_names(ref_prop['type'])) if ref_prop
    end
  end

  if array_type && prop['items'].is_a?(Hash)
    collect_refs.call(prop['items'])
  else
    collect_refs.call(prop)
  end

  entry = {
    'name'        => field_name,
    'type'        => array_type ? 'array' : 'ref',
    'refs'        => refs.flatten.uniq,
    'description' => nil
  }
  entry['readonly'] = true if prop['readonly'] == true || prop['readonly'] == 'true'
  entry
end

# ---------------------------------------------------------------------------
# Type normalization helpers
#
# Schema types can be:
#   "string", "boolean", "integer", "date", "object", "array"
#   "JSONModel(:foo) object"  - embedded sub-record of type foo
#   "JSONModel(:foo) uri"     - URI reference to a foo record
#   [{"type" => "JSONModel(:a) uri"}, {"type" => "JSONModel(:b) uri"}] - union
# ---------------------------------------------------------------------------
def normalize_type(raw)
  case raw
  when Array
    parts = raw.map { |t| normalize_type(t.is_a?(Hash) ? t['type'] : t.to_s) }.uniq
    parts.length == 1 ? parts.first : parts.join(' | ')
  when /\AJSONModel\(:([^)]+)\) uri\z/
    "string (uri)"
  when /\AJSONModel\(:([^)]+)\) object\z/
    "object"
  when /\AJSONModel\(:([^)]+)\)\z/
    "object"
  when String
    raw.empty? ? nil : raw
  when Hash
    normalize_type(raw['type'])
  else
    raw.to_s
  end
end

# For an array field's items definition, return the embedded record type name(s).
# Returns a String for a single type, Array for union types, or nil if not a JSONModel ref.
def items_record_type(items_def)
  return nil unless items_def.is_a?(Hash)
  extract_jsonmodel_names(items_def['type'])
end

# For a "subtype: ref" items definition, return the list of referenceable record types.
def ref_types(items_def)
  return nil unless items_def.is_a?(Hash) && items_def['subtype'] == 'ref'
  ref_prop = items_def.dig('properties', 'ref')
  return nil unless ref_prop
  extract_jsonmodel_names(ref_prop['type'])
end

def extract_jsonmodel_names(type_val)
  case type_val
  when String
    m = type_val.match(/JSONModel\(:([^)]+)\)/)
    m ? m[1] : nil
  when Array
    names = type_val.map { |t|
      s = t.is_a?(Hash) ? t['type'].to_s : t.to_s
      m = s.match(/JSONModel\(:([^)]+)\)/)
      m ? m[1] : nil
    }.compact.uniq
    return nil if names.empty?
    names.length == 1 ? names.first : names
  else
    nil
  end
end

# ---------------------------------------------------------------------------
# Step 4a: Parse demo.sql.gz to extract first non-null example value per column
#
# Reads the MySQL dump line-by-line:
#   - CREATE TABLE statements supply the ordered column list for each table.
#   - INSERT INTO ... VALUES lines supply the actual data rows.
#
# Returns a hash keyed by table name, with each value being a flat hash of
# { column_name => first_non_null_value }.  Columns whose names end in "_id"
# are excluded because they hold opaque foreign-key integers, not useful examples.
# ---------------------------------------------------------------------------
def parse_demo_db(gz_path)
  require 'zlib'
  return {} unless gz_path && File.exist?(gz_path)

  table_columns  = {}  # table_name => [col1, col2, ...]
  table_examples = {}  # table_name => { col_name => first_non_null_value }

  Zlib::GzipReader.open(gz_path) do |gz|
    current_table = nil

    gz.each_line do |line|
      line.chomp!

      # Detect the start of a CREATE TABLE block — grab the table name
      if line =~ /^CREATE TABLE `([^`]+)`/
        current_table = $1
        table_columns[current_table] = []

      # Inside a CREATE TABLE block: collect column names (lines that start with a backtick-quoted name)
      elsif current_table && line =~ /^\s+`([^`]+)` /
        table_columns[current_table] << $1

      # End of CREATE TABLE block
      elsif line =~ /^\) ENGINE=/
        current_table = nil

      # INSERT INTO `table` VALUES (…),(…);
      elsif line =~ /^INSERT INTO `([^`]+)` VALUES (.+?);\s*$/
        table_name  = $1
        values_part = $2
        cols = table_columns[table_name]
        next unless cols

        examples = table_examples[table_name] ||= {}

        parse_sql_rows(values_part) do |row|
          row.each_with_index do |val, idx|
            col = cols[idx]
            next unless col
            next if col.end_with?('_id')              # skip FK integer references
            next if val.nil? || (val.is_a?(String) && val.strip.empty?)
            examples[col] ||= val                     # keep first non-null value
          end
          # Stop scanning once every column has an example
          break if examples.length >= cols.reject { |c| c.end_with?('_id') }.length
        end
      end
    end
  end

  table_examples
end

# Tokenize a MySQL VALUES string into rows.  Each row is an Array of Ruby values:
#   nil       → SQL NULL
#   Integer   → unquoted integer literal
#   Float     → unquoted decimal literal
#   String    → single-quoted string (escape sequences resolved)
#
# Yields each row array to the caller.
def parse_sql_rows(str)
  i = 0
  n = str.length

  while i < n
    # Advance to the opening parenthesis of the next row
    i += 1 until i >= n || str[i] == '('
    break if i >= n
    i += 1  # consume '('

    row = []

    loop do
      break if i >= n || str[i] == ')'

      if str[i] == "'"
        # Single-quoted string: resolve MySQL escape sequences
        i += 1
        buf = +''
        while i < n
          ch = str[i]
          if ch == '\\'
            i += 1
            buf << case str[i]
                   when 'n'  then "\n"
                   when 'r'  then "\r"
                   when 't'  then "\t"
                   when '\'' then "'"
                   when '\\' then "\\"
                   else str[i]          # handles \" → " and other escapes
                   end
          elsif ch == "'"
            i += 1  # consume closing quote
            break
          else
            buf << ch
          end
          i += 1
        end
        row << buf

      elsif str[i..i+3] == 'NULL'
        row << nil
        i += 4

      else
        # Unquoted value: integer, float, or bare keyword
        j = i
        i += 1 while i < n && str[i] != ',' && str[i] != ')'
        token = str[j...i]
        row << if token =~ /\A-?\d+\z/
                 token.to_i
               elsif token =~ /\A-?\d+\.\d+\z/
                 token.to_f
               else
                 token
               end
      end

      i += 1 if i < n && str[i] == ','  # consume comma separator
    end

    yield row
    i += 1  # consume ')'
    i += 1 if i < n && str[i] == ','   # consume comma between rows
  end
end

# Format a raw DB value as a human-readable example string.
# Returns nil for values that make poor examples (zero, empty strings, etc.).
def format_db_example(val, schema_type)
  return nil if val.nil?

  case schema_type
  when 'boolean'
    # MySQL stores booleans as tinyint 0/1
    val == 0 ? false : true
  when 'integer'
    val.is_a?(Integer) ? val : nil
  else
    s = val.to_s.strip
    return nil if s.empty?
    s.length > 250 ? "#{s[0, 250]}..." : s
  end
end

# ---------------------------------------------------------------------------
# Step 4: Build a single field entry from a schema property hash
# ---------------------------------------------------------------------------
def build_field(field_name, prop, record_type, locales, db_example: nil)
  entry = {}
  entry['name'] = field_name

  raw_type = prop['type']
  entry['type'] = normalize_type(raw_type) || 'string'

  # Description — not derivable from schema; left for manual enrichment
  entry['description'] = nil

  # Labels from locale files
  entry['staff_label'] = lookup_label(
    [locales[:common], locales[:frontend]], record_type, field_name
  )
  entry['public_label'] = lookup_label(
    [locales[:public]], record_type, field_name
  )

  # required: true only when ifmissing is explicitly "error"
  entry['required'] = prop['ifmissing'] == 'error'

  # readonly: true when schema marks the field as system-generated
  entry['readonly'] = prop['readonly'] == true || prop['readonly'] == 'true'

  # Default value, if declared in the schema
  entry['default'] = prop['default'] if prop.key?('default')

  # Controlled vocabulary
  entry['dynamic_enum'] = prop['dynamic_enum'] if prop['dynamic_enum']
  entry['enum']         = prop['enum']         if prop['enum']

  # Validation constraints
  entry['max_length'] = prop['maxLength'] if prop['maxLength']
  entry['pattern']    = prop['pattern']   if prop['pattern']

  # Array item type and relationship refs
  if raw_type == 'array' && prop['items']
    items_def = prop['items']
    it = items_record_type(items_def)
    rt = ref_types(items_def)
    entry['items'] = it if it
    entry['refs']  = rt if rt

    # For arrays of primitives (string, integer) capture the items type
    if it.nil? && rt.nil? && items_def.is_a?(Hash)
      prim = items_def['type']
      entry['items'] = prim if prim.is_a?(String) && !prim.empty?
    end

    # Minimum cardinality constraint
    entry['min_items'] = prop['minItems'] if prop['minItems']

  elsif raw_type.is_a?(Array)
    # Union of URI/object types at the field level (e.g. derived_from on file_version)
    ref_names = raw_type.filter_map { |t|
      s = t.is_a?(Hash) ? t['type'].to_s : t.to_s
      m = s.match(/JSONModel\(:([^)]+)\)/)
      m ? m[1] : nil
    }.uniq
    entry['refs'] = ref_names unless ref_names.empty?
  end

  # Example value sourced from demo database, or nil if unavailable
  entry['example']              = format_db_example(db_example, entry['type'])
  entry['export_mappings']      = nil
  entry['solr_field']           = nil
  entry['solr_index']           = nil
  entry['solr_note']            = nil
  entry['required_permission']  = nil
  entry['conditions']           = nil
  entry['version_note']         = nil

  entry
end

# ---------------------------------------------------------------------------
# Step 5: Determine which interfaces display a record type and which output
#         section (record_types / subrecord_types / note_types) it belongs to.
#
# ui_display heuristics:
#   - Schema names beginning with "abstract_" → abstract (not rendered directly)
#   - Schemas with a top-level "uri" key → at minimum staff-visible
#   - Common public-facing archival types → staff + public
#
# Section classification:
#   - NOTE_SCHEMAS → note_types section
#   - Has URI OR starts with "abstract_" → record_types section
#   - Everything else (not skipped) → subrecord_types section
# ---------------------------------------------------------------------------
ABSTRACT_PREFIXES = %w[abstract_].freeze

PUBLIC_RECORD_TYPES = %w[
  resource archival_object digital_object digital_object_component
  agent_person agent_corporate_entity agent_family agent_software
  subject classification classification_term
  top_container location date extent file_version
].freeze

# All note-related schemas (those starting note_ plus abstract_note)
NOTE_SCHEMAS = (
  %w[abstract_note] +
  Dir.glob(File.join(File.expand_path('../../common/schemas', __FILE__), 'note_*.rb'))
     .map { |p| File.basename(p, '.rb') }
).freeze

# Schemas with no top-level URI that should be classified as record_types
# (not subrecord_types) because they are meaningful standalone data containers.
FORCE_RECORD_TYPES = %w[date extent file_version instance rights_statement].freeze

# Schemas that should be classified as subrecord_types regardless of URI or
# abstract_ prefix, because they are always embedded in parent records.
FORCE_SUBRECORD_TYPES = %w[abstract_name collection_management].freeze

# Curated common subsets of the ISO 639-2 (language) and ISO 15924 (script)
# code lists. The full lists live in common/locales/enums/en.yml with 480+
# and 190+ entries respectively; these are the most frequently encountered
# values and are added as convenience references.
LANGUAGE_ISO639_2_COMMON = %w[
  ara ben dan deu eng fin fra hin ita jpn kor nld nor pol por rus spa swe tur zho
].freeze

SCRIPT_ISO15924_COMMON = %w[
  Arab Cyrl Deva Grek Hang Hans Hant Hebr Hira Latn Thai Tibt
].freeze

def ui_display_for(record_type, schema)
  return ['abstract'] if ABSTRACT_PREFIXES.any? { |p| record_type.start_with?(p) }
  return ['staff', 'public'] if PUBLIC_RECORD_TYPES.include?(record_type)
  ['staff']
end

# Returns which top-level output section this schema belongs to:
#   :record_type, :subrecord_type, or :note_type
def schema_section(name, schema)
  return :note_type      if NOTE_SCHEMAS.include?(name)
  return :record_type    if FORCE_RECORD_TYPES.include?(name)
  return :subrecord_type if FORCE_SUBRECORD_TYPES.include?(name)
  return :record_type    if schema['uri'].is_a?(String) || name.start_with?('abstract_')
  :subrecord_type
end

# ---------------------------------------------------------------------------
# Note type helpers
#
# used_on: which concrete record types reference a given note type in their
#   schema properties (directly or via an inherited parent schema).
#
# allowed_type_values: the controlled vocabulary for a note's "type" field,
#   derived from the dynamic_enum value and the parsed enumerations table.
# ---------------------------------------------------------------------------

# Extract all note schema names referenced in a type value (string or array).
def extract_note_refs(type_val)
  refs = []
  case type_val
  when String
    m = type_val.match(/JSONModel\(:([^)]+)\)/)
    refs << m[1] if m && m[1].start_with?('note_')
  when Array
    type_val.each do |t|
      s = t.is_a?(Hash) ? t['type'].to_s : t.to_s
      m = s.match(/JSONModel\(:([^)]+)\)/)
      refs << m[1] if m && m[1].start_with?('note_')
    end
  end
  refs
end

# Build a reverse index: note_type_name => [concrete record/subrecord type names].
# Abstract schemas (e.g. abstract_agent) are expanded to their concrete children.
def build_note_used_on(raw_schemas)
  # parent => [children] map
  children_of = Hash.new { |h, k| h[k] = [] }
  raw_schemas.each do |name, raw|
    parent = raw[:schema]['parent']
    children_of[parent] << name if parent.is_a?(String)
  end

  # Expand a schema name to concrete (leaf or non-abstract) descendants
  expand_to_concrete = lambda do |name|
    kids = children_of[name]
    if kids.empty?
      name.start_with?('abstract_') ? [] : [name]
    else
      expanded = kids.flat_map { |c| expand_to_concrete.call(c) }
      name.start_with?('abstract_') ? expanded : [name] + expanded
    end
  end

  note_used_on = Hash.new { |h, k| h[k] = [] }

  raw_schemas.each do |schema_name, raw|
    next if NOTE_SCHEMAS.include?(schema_name)
    next if SKIP_SCHEMAS.include?(schema_name)

    properties = raw[:schema]['properties'] || {}
    note_refs  = []

    properties.each_value do |prop|
      next unless prop.is_a?(Hash)
      type_val = prop['type'] == 'array' && prop['items'].is_a?(Hash) ? prop['items']['type'] : prop['type']
      note_refs.concat(extract_note_refs(type_val))
    end

    next if note_refs.empty?

    expand_to_concrete.call(schema_name).each do |concrete|
      note_refs.uniq.each do |note_name|
        note_used_on[note_name] |= [concrete]
      end
    end
  end

  note_used_on
end

# ---------------------------------------------------------------------------
# Schema files to skip — internal/operational types not useful in a data
# dictionary (jobs, queries, tree views, batch operations, etc.)
# ---------------------------------------------------------------------------
SKIP_SCHEMAS = %w[
  active_edits
  advanced_query
  archival_record_children
  assessment_attribute
  boolean_field_query
  boolean_query
  bulk_archival_object_updater_job
  bulk_import_job
  classification_tree
  container_conversion_job
  container_labels_job
  custom_report_template
  date_field_query
  default_values
  defaults
  digital_object_tree
  digital_record_children
  enumeration
  enumeration_migration
  enumeration_value
  field_query
  find_and_replace_job
  generate_arks_job
  generate_slugs_job
  group
  import_job
  job
  location_batch
  location_batch_update
  merge_request
  merge_request_detail
  ns2_remover_job
  oai_config
  permission
  preference
  print_to_pdf_job
  range_query
  rde_template
  record_tree
  report_job
  repository_with_agent
  required_fields
  resource_duplicate_job
  resource_ordered_records
  resource_tree
  subrecord_requirement
  top_container_linker_job
  trim_whitespace_job
  vocabulary
].freeze

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
puts
puts "=" * 65
puts "  GENERATE DATA DICTIONARY"
puts "  Repo: #{REPO_ROOT}"
puts "  Output: #{options[:output]}"
puts "=" * 65

# -- Enumerations --
print "\n  Loading enumerations from migrations... "
enumerations = parse_enumerations(File.join(REPO_ROOT, 'common/db/migrations'))
puts "#{enumerations.size} enumerations found"

# -- Locales --
print "  Loading locale files... "
locales = load_locales(REPO_ROOT)
staff_label_count = locales[:common].values.sum { |v| v.is_a?(Hash) ? v.count { |_, lv| lv.is_a?(String) } : 0 }
puts "done (#{staff_label_count}+ staff label entries)"

# -- Demo database examples --
if options[:demo_db]
  print "  Loading examples from #{File.basename(options[:demo_db])}... "
  demo_data = parse_demo_db(options[:demo_db])
  covered = demo_data.values.sum(&:size)
  puts "#{demo_data.size} tables, #{covered} column examples found"
else
  demo_data = {}
  puts "  Skipping demo database (--no-examples)"
end

# -- Schemas --
schema_dir   = File.join(REPO_ROOT, 'common/schemas')
schema_paths = Dir.glob(File.join(schema_dir, '*.rb')).sort
puts "  Found #{schema_paths.size} schema files in common/schemas/"

record_types    = {}
subrecord_types = {}
note_types      = {}
skipped_names   = []
failed_names    = []

# -- Pass 1: Load all raw schemas (needed to classify fields as subrecords/relationships) --
print "  Loading all schema files... "
raw_schemas = {}
schema_paths.each do |path|
  name = File.basename(path, '.rb')
  next if SKIP_SCHEMAS.include?(name)
  raw  = load_schema(path)
  raw_schemas[name] = raw if raw.is_a?(Hash) && raw[:schema].is_a?(Hash)
end
puts "#{raw_schemas.size} loaded"

# -- Build note used_on index (requires all schemas loaded) --
print "  Building note used_on index... "
note_used_on = build_note_used_on(raw_schemas)
puts "#{note_used_on.size} note types mapped"

# -- Pass 2: Build entries and assign each schema to the correct output section --
schema_paths.each do |path|
  name = File.basename(path, '.rb')

  if SKIP_SCHEMAS.include?(name)
    skipped_names << name
    next
  end

  raw = raw_schemas[name]
  unless raw
    failed_names << name
    next
  end

  schema     = raw[:schema]
  properties = schema['properties'] || {}
  parent     = schema['parent'].is_a?(String) ? schema['parent'] : nil

  # Column-level examples for this record type's backing table (if present in demo DB)
  table_examples = demo_data[name] || {}

  # Classify each property into simple fields, embedded subrecords, or relationships
  fields        = []
  subrecords    = []
  relationships = []

  properties.each do |field_name, prop|
    next unless prop.is_a?(Hash)
    next if field_name.start_with?('_')

    case classify_field(prop, raw_schemas)
    when :subrecord
      subrecords << build_subrecord_entry(field_name, prop)
    when :relationship
      relationships << build_relationship_entry(field_name, prop, raw_schemas)
    else
      fields << build_field(field_name, prop, name, locales, db_example: table_examples[field_name])
    end
  end

  inherited_fields = build_inherited_fields_note(name, raw_schemas)

  entry = {
    'description'         => nil,
    'api_endpoint'        => schema['uri'],
    'scope'               => derive_scope(schema['uri']) || EMBEDDED_RECORD_SCOPES[name],
    'parent_schema'       => parent,
    'ui_display'          => ui_display_for(name, schema),
    'field_ui_visibility' => { 'staff_only' => [], 'api_only' => [] },
    'fields'              => fields,
    'inherited_fields'    => inherited_fields,
    'subrecords'          => subrecords,
    'relationships'       => relationships
  }
  case schema_section(name, schema)
  when :note_type
    # Add used_on: which record/subrecord types reference this note type
    used_on = note_used_on[name]
    entry['used_on'] = used_on.empty? ? nil : used_on.sort

    # Add allowed_type_values: controlled vocab for the note's "type" field,
    # derived from the dynamic_enum of the "type" property.
    type_prop = properties['type']
    if type_prop.is_a?(Hash) && (enum_name = type_prop['dynamic_enum'])
      entry['allowed_type_values'] = enumerations[enum_name] || nil
    else
      entry['allowed_type_values'] = nil
    end

    note_types[name] = entry
  when :subrecord_type
    subrecord_types[name] = entry
  else
    record_types[name] = entry
  end
end

puts "  Record types:    #{record_types.size}"
puts "  Subrecord types: #{subrecord_types.size}"
puts "  Note types:      #{note_types.size}"
puts "  Skipped (internal/operational): #{skipped_names.size}"
puts "  Failed to parse: #{failed_names.join(', ')}" unless failed_names.empty?

# -- Assemble output --
today = Date.today.iso8601
output = {
  'metadata' => {
    'generated_at' => today,
    'last_updated' => today,
    'source'       => 'common/schemas/',
    'description'  => 'Data dictionary for all ArchivesSpace record types, ' \
                       'derived from JSONModel schema definitions. ' \
                       'Fields marked required:true will produce validation errors if ' \
                       'missing (ifmissing:error). Fields marked readonly:true are ' \
                       'computed by the system and cannot be set by the client.',
    'schema_url'   => 'http://www.archivesspace.org/archivesspace.json',
    'label_sources' => {
      'staff_label'  => 'Label as shown in the Staff Interface (frontend/). ' \
                        'Sourced from common/locales/en.yml and frontend/config/locales/en.yml.',
      'public_label' => 'Label as shown in the Public Interface (public/). ' \
                        'Sourced from public/config/locales/en.yml and public view templates. ' \
                        'null if not displayed in the public interface.'
    },
    'ui_display_key' => {
      'note' => "Each record type includes a 'ui_display' array indicating which " \
                "interfaces render that record type, and a 'field_ui_visibility' object " \
                "listing per-field exceptions.",
      'ui_display_values' => {
        'staff'    => 'Visible in the Staff Interface (frontend, port 3000) — ' \
                      'editable forms and show views for archivists and administrators.',
        'public'   => 'Visible in the Public Interface (port 3001) — ' \
                      'read-only discovery views for end users. ' \
                      'Only records with publish:true appear here.',
        'abstract' => 'Not a standalone record type; shared base schema only. ' \
                      'Not rendered directly in any UI.'
      },
      'field_ui_visibility' => {
        'staff_only' => 'Fields rendered in the Staff Interface but NOT in the Public Interface.',
        'api_only'   => 'System-generated or internal fields not directly rendered in any UI ' \
                        'form or show view. Accessible via API only.'
      }
    },
    'common_system_fields' => {
      'note' => 'All persisted records include the following system-managed fields in the database',
      'fields' => [
        { 'name' => 'lock_version',       'type' => 'integer',  'description' => 'Optimistic locking version counter',                    'staff_label' => nil,              'public_label' => nil },
        { 'name' => 'json_schema_version','type' => 'integer',  'description' => 'Schema version at time of last save',                    'staff_label' => nil,              'public_label' => nil },
        { 'name' => 'created_by',         'type' => 'string',   'description' => 'Username that created the record',                       'staff_label' => 'Created By',     'public_label' => nil },
        { 'name' => 'last_modified_by',   'type' => 'string',   'description' => 'Username that last modified the record',                 'staff_label' => 'Last Modified By','public_label' => nil },
        { 'name' => 'create_time',        'type' => 'datetime', 'description' => 'Record creation timestamp',                              'staff_label' => 'Created',        'public_label' => nil },
        { 'name' => 'system_mtime',       'type' => 'datetime', 'description' => 'System modification timestamp (updated on any change)',  'staff_label' => nil,              'public_label' => nil },
        { 'name' => 'user_mtime',         'type' => 'datetime', 'description' => 'User modification timestamp (updated on user-initiated changes)', 'staff_label' => 'Last Modified', 'public_label' => nil },
      ]
    }
  },
  'enumerations' => {
    '_note' => 'Allowed values for all dynamic enumerations referenced by fields. ' \
               'Sourced from common/db/migrations/ and common/locales/enums/en.yml. ' \
               'Editable enumerations may have additional values added by administrators at runtime.',
    'language_iso639_2_common' => LANGUAGE_ISO639_2_COMMON,
    'script_iso15924_common'   => SCRIPT_ISO15924_COMMON
  }.merge(enumerations),
  'record_types'    => record_types,
  'subrecord_types' => {
    '_note' => 'Embedded subrecord schemas referenced by record_types. These are not standalone ' \
               'API resources but appear as embedded objects within parent records.'
  }.merge(subrecord_types),
  'note_types' => {
    '_note' => 'Note schemas used within archival records and agent records. Notes are the ' \
               'primary vehicle for free-text description in ArchivesSpace.'
  }.merge(note_types),
  'record_examples' => {
    '_note' => 'Complete API JSON payloads showing realistic records. These represent what ' \
               'the ArchivesSpace REST API returns for GET requests on individual records.'
  }
}

# ---------------------------------------------------------------------------
# Enrichment preservation
#
# Carry forward any non-null manually enriched values from the existing output
# file into the freshly generated output.  This means re-running the generator
# will not wipe out descriptions, examples, export_mappings, solr fields, etc.
# that were hand-authored in a previous pass.
#
# Enrichable attributes — values that come from human research, not schemas:
ENRICHABLE_ATTRS = %w[
  description example export_mappings
  solr_field solr_index solr_note
  public_label conditions required_permission version_note
].freeze

# Merge enrichments from +existing+ into +generated+ in place.
# Works across record_types, subrecord_types, and note_types:
#   - Top-level entry description
#   - Per-field enrichable attributes
#   - record_examples entries (always preserved; generator always outputs empty)
def preserve_enrichments(generated, existing)
  enriched = 0

  %w[record_types subrecord_types note_types].each do |section|
    (existing[section] || {}).each do |key, ex_entry|
      next if key == '_note'
      next unless ex_entry.is_a?(Hash)
      gen_entry = (generated[section] || {})[key]
      next unless gen_entry.is_a?(Hash)

      # Top-level description
      if ex_entry['description'] && gen_entry['description'].nil?
        gen_entry['description'] = ex_entry['description']
        enriched += 1
      end

      # Field-level attributes
      ex_fields  = (ex_entry['fields']  || []).each_with_object({}) { |f, h| h[f['name']] = f if f['name'] }
      gen_fields = (gen_entry['fields'] || [])

      gen_fields.each do |gf|
        ef = ex_fields[gf['name']]
        next unless ef
        ENRICHABLE_ATTRS.each do |attr|
          if !ef[attr].nil? && gf[attr].nil?
            gf[attr] = ef[attr]
            enriched += 1
          end
        end
      end
    end
  end

  # record_examples: keep all hand-authored entries the generator leaves empty
  (existing['record_examples'] || {}).each do |key, val|
    next if key == '_note'
    unless (generated['record_examples'] || {}).key?(key)
      generated['record_examples'] ||= {}
      generated['record_examples'][key] = val
      enriched += 1
    end
  end

  enriched
end

# -- Write or dry-run --
if options[:dry_run]
  puts "\n  --dry-run: no file written."
  puts "  Would write to #{options[:output]}:"
  puts "    #{record_types.size} record types, #{subrecord_types.size} subrecord types, " \
       "#{note_types.size} note types, #{enumerations.size} enumerations"
else
  if File.exist?(options[:output]) && !options[:force]
    print "\n  #{File.basename(options[:output])} already exists. Overwrite? [y/N] "
    answer = $stdin.gets.to_s.strip.downcase
    unless answer == 'y'
      puts "  Aborted. Use --output to write to a different path, or --force to overwrite."
      exit 0
    end
  end

  if options[:preserve_enrichments] && File.exist?(options[:output])
    existing = JSON.parse(File.read(options[:output]))
    enriched_count = preserve_enrichments(output, existing)
    puts "  Preserved #{enriched_count} manual enrichments from existing file" if enriched_count > 0
  end

  File.write(options[:output], JSON.pretty_generate(output))
  size_kb = (File.size(options[:output]) / 1024.0).round(1)
  puts "\n  Written: #{options[:output]} (#{size_kb} KB)"
  puts "  Record types:    #{record_types.size}"
  puts "  Subrecord types: #{subrecord_types.size}"
  puts "  Note types:      #{note_types.size}"
  puts "  Enumerations:    #{enumerations.size}"
  puts
  puts "  Next steps — manually enrich null fields:"
  puts "    description, example, export_mappings,"
  puts "    solr_field, solr_index, solr_note,"
  puts "    conditions, required_permission, version_note"
  puts "  Use scripts/update_data_dictionary.rb to merge enrichments incrementally."
end
puts
