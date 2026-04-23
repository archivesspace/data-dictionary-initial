# ArchivesSpace Data Dictionary

A Rails 8 web application providing a searchable data dictionary for [ArchivesSpace](https://archivesspace.org/). It documents database fields, their types, descriptions, validation rules, and how they appear in the staff and public interfaces.

## Intended Use

This application is intended to help the ArchivesSpace community understand where data is stored in the ArchivesSpace database and how it is displayed in the staff and public interfaces. It is useful for writing reports, working with the ArchivesSpace API, and developing application code.

## Requirements

- Ruby (see `.ruby-version`)
- Rails 8
- PostgreSQL

## Setup

```bash
# Install dependencies
bundle install

# Create and load the database
bin/rails db:create db:schema:load

# Start the development server
bin/rails s
```

## Running with Docker

A `Dockerfile` and `compose.yaml` are provided to run the app (and a PostgreSQL 16 database) in containers.

### Prerequisites

- Docker Dekstop or Docker Engine 24+.

### Quick start

```bash
# Build the image and start the app + database
docker compose up
```

Then browse to <http://localhost:3000>.

On first startup the web container will:

1. Create the database schema (`rails db:prepare`).
2. Seed the database from `data_dictionary.json` at the repo root.

Subsequent starts skip seeding.


## Importing Data

### From a JSON file

Place a `data_dictionary.json` file in the Rails root directory and run:

```bash
bin/rails import:json
```

To import from a different path:

```bash
bin/rails "import:json[/path/to/data_dictionary.json]"
```

The task upserts records by `field_id` (derived from field name + table name), so it is safe to re-run — existing fields will be updated and new ones added.

To wipe all existing field data and reload from a fresh JSON file:

```bash
bin/rails import:reset
```

To reset using a file at a different path:

```bash
bin/rails "import:reset[/path/to/data_dictionary.json]"
```

### From a spreadsheet

Navigate to the Fields list and use the import form to upload an `.xlsx`, `.xls`, or `.csv` file. Each sheet in the workbook becomes a table name; rows become fields. Records are upserted by `field_id`, so re-uploading is safe.

## Running Tests

```bash
# Cucumber acceptance tests
bundle exec cucumber

# Run a single feature
bundle exec cucumber features/search.feature

# RSpec unit tests
bundle exec rspec
```

## Future Enhancements

Planned enhancements include:

- Crosswalk information for metadata standards (EAD, MARC, MODS, DC)
- Highlighting search results in context
- Sort capability from column headings
- Exporting search results

## Special Thanks

This application would not be possible without the work of the ArchivesSpace User Advisory Council Reports Sub-team, particularly the extraordinary efforts by Nancy Enneking.
