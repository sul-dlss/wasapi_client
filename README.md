[![CircleCI](https://dl.circleci.com/status-badge/img/gh/sul-dlss/wasapi_client/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/sul-dlss/wasapi_client/tree/main)
[![codecov](https://codecov.io/gh/sul-dlss/wasapi_client/graph/badge.svg?token=O48G6RUM9K)](https://codecov.io/gh/sul-dlss/wasapi_client)

# WasapiClient

WasapiClient is a Ruby gem that acts as a client to Internet Archive's WASAPI APIs. It gets information about WARCs and downloads them. It is a successor to wasapi-downloader but is not provider-generic and is intended for use with Archive-It collections. 

## Installation

Once the gem has been published, it will be possible to install the gem and add to the application's Gemfile by executing:

```
bundle add wasapi_client
```

If bundler is not being used to manage dependencies, install the gem by executing:

```
gem install wasapi_client
```

## Usage

Each Archive-It account has its own username and password for downloading WARCs. An account includes many collections, which each have a numeric id. Since we have many accounts, when making requests we need to provide the username and password for the account to which the Archive-It collection belongs. 

```ruby
require 'wasapi_client'

# NOTE: The settings below live in the consumer, not in the gem.
client = WasapiClient.new(username: 'username', password: 'password')
client.fetch_warcs(
  output_dir: 'path/to/save/warcs',
  collection: '12345',
  crawl_start_after: '2023-01-01',
  crawl_start_before: '2023-01-31'
)

# Get filenames for a collection (used when auditing)
client.filenames(
  collection: '12345',
  crawl_start_after: '2025-01-01',
  crawl_start_before: '2025-06-30'
)

# Fetch a single WARC by URL
client.fetch_file(
  file: 'https://warcs.archive-it.org/webdatafile/ARCHIVEIT-123-example.warc.gz',
  output_dir: 'path/to/save/warcs'
)

# Fetch a single WARC by filename (used when auditing/remediating)
client.fetch_file(
  file: 'ARCHIVEIT-123-example.warc.gz',
  output_dir: 'path/to/save/warcs',
  base_url: 'https://other-archive-it-location.org'
)

# Get the URLs for WARCs meeting collection and crawl time criteria
client.get_locations(
  collection: '12345',
  crawl_start_after: '2025-01-01',
  crawl_start_before: '2025-06-30'
)
```

## TODO
* Add store-time- params to support usage with backfill downloads


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. 

To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).
