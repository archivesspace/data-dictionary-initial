# Data Dictionary

The repository includes a `data_dictionary.json` file that documents all ArchivesSpace record types, their fields, and field metadata derived from the JSONModel schema definitions in `common/schemas/`.

## Structure

The file has three top-level keys:

- **`metadata`** — provenance, timestamps, and documentation for the file itself
- **`enumerations`** — allowed values for dynamic enumerations referenced by fields
- **`record_types`** — a map of record type name → record type object

Each record type object contains:
- `description` — what the record type represents
- `ui_display` — which interfaces render this type (`staff`, `public`, or `abstract`)
- `fields` — array of field objects
- `subrecords` — array of embedded sub-record definitions (optional)
- `relationships` — array of relationship definitions (optional)

Each field object uses these canonical properties:

| Key | Description |
|---|---|
| `name` | Field name as used in the API/schema |
| `type` | Data type (`string`, `integer`, `boolean`, `object`, `array`, `datetime`, etc.) |
| `description` | What the field stores |
| `staff_label` | Label shown in the Staff Interface (`null` if not displayed) |
| `public_label` | Label shown in the Public Interface (`null` if not displayed) |
| `required` | `true` if the system will reject records missing this field |
| `readonly` | `true` if the field is system-generated and cannot be set by clients |
| `example` | An example value (optional) |
| `default` | Default value applied when the field is omitted (optional) |
| `enum` | Array of allowed literal values for fields with a fixed controlled vocabulary (optional) |
| `dynamic_enum` | Name of the enumeration list whose allowed values are managed at runtime via the Manage Controlled Value Lists page (optional) |
| `conditions` | Conditional validation rules, e.g. making a field required only when another field has a specific value (optional) |
| `pattern` | Regex or human-readable pattern the value must match (optional) |
| `max_length` | Maximum character length for string fields (optional) |
| `min_items` | Minimum number of items required for array fields (optional) |
| `items` | For `array`-typed fields, the record type name of each array element (optional) |
| `refs` | For relationship/link fields, the list of record types this field may reference (optional) |
| `required_permission` | Permission code a user must hold to read or set this field (optional) |
| `export_mappings` | How this field maps to export formats (`ead`, `marc`, `dc`); `null` means not exported in that format (optional) |
| `solr_field` | Solr field name this value is indexed into (optional) |
| `solr_index` | Indexing strategy: `indexed` (exact match), `full_text` (tokenized search), etc. (optional) |
| `solr_note` | Human-readable note describing the Solr indexing behavior (optional) |
| `version_note` | ArchivesSpace version when this field was added or changed, with a short note (optional) |

## Regenerating the data dictionary from scratch

Copy the generate_data_dictionary.rb and update_data_dictionary.rb scripts to the archivesspace/scripts directory to run

`scripts/generate_data_dictionary.rb` reads the ArchivesSpace source files directly and rebuilds `data_dictionary.json` from scratch:

```bash
# Preview — prints a summary without writing anything
ruby --disable-gems scripts/generate_data_dictionary.rb --dry-run

# Generate and write to data_dictionary.json (prompts before overwriting)
ruby --disable-gems scripts/generate_data_dictionary.rb

# Write to a different path
ruby --disable-gems scripts/generate_data_dictionary.rb --output path/to/output.json

# Overwrite without prompting
ruby --disable-gems scripts/generate_data_dictionary.rb --force

# Use a different demo database fixture for examples
ruby --disable-gems scripts/generate_data_dictionary.rb --demo-db path/to/demo.sql.gz

# Skip example extraction entirely
ruby --disable-gems scripts/generate_data_dictionary.rb --no-examples
```

The script reads from:

| Source | What it provides |
|---|---|
| `common/schemas/*.rb` | Field names, types, constraints (`maxLength`, `pattern`), required/readonly flags, `dynamic_enum`, `default`, `items`, `refs` |
| `common/locales/en.yml` | Staff interface field labels (shared) |
| `frontend/config/locales/en.yml` | Staff interface field labels (frontend-specific) |
| `public/config/locales/en.yml` | Public interface field labels |
| `common/db/migrations/*.rb` | Enumeration value lists |
| `build/mysql_db_fixtures/demo.sql.gz` | Example values for fields (populated automatically where available) |

The script automatically populates `example` values by reading `build/mysql_db_fixtures/demo.sql.gz`. For each record type whose name matches a database table, the first non-null value found in the demo data is used as the example for each matching field. Fields that store opaque foreign-key IDs (`*_id` columns) are excluded. Pass `--no-examples` to skip this step, or `--demo-db PATH` to use a different fixture file.

The following fields still require manual enrichment and are written as `null` when the demo database cannot supply them: `description`, `example` (for fields without a matching DB column), `export_mappings`, `solr_field`, `solr_index`, `solr_note`, `conditions`, `required_permission`, `version_note`.

After regenerating, use `scripts/update_data_dictionary.rb` to merge in a file containing your manual enrichments (see below).

## Creating a new data dictionary file

To add or update record types, create a new JSON file with the same structure as `data_dictionary.json` containing only the record types you want to add or change:

```json
{
  "record_types": {
    "my_record_type": {
      "description": "Description of this record type.",
      "ui_display": ["staff"],
      "fields": [
        {
          "name": "title",
          "type": "string",
          "description": "The title of the record.",
          "staff_label": "Title",
          "public_label": "Title",
          "required": true,
          "readonly": false,
          "example": "My Collection"
        }
      ]
    }
  }
}
```

You do not need to include a `metadata` key — the update script manages timestamps automatically.

## Merging changes into data_dictionary.json

Use `scripts/update_data_dictionary.rb` to merge your new file into the canonical dictionary:

```bash
# Preview changes without writing anything
ruby --disable-gems scripts/update_data_dictionary.rb my_new_entries.json --dry-run

# Apply changes (updates data_dictionary.json in place)
ruby --disable-gems scripts/update_data_dictionary.rb my_new_entries.json

# Write to a different output file instead
ruby --disable-gems scripts/update_data_dictionary.rb my_new_entries.json --output path/to/output.json
```

The script prints a color-coded changelog showing every added, removed, and modified field, then updates `data_dictionary.json` and appends an entry to its `changelog` array. Existing record types not present in your new file are preserved unchanged.
