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
```

## TODO
* Unit tests
* Download a single file by filename
* Add store-time- params to support usage with backfill downloads (not in wasapi_downloader)
* Support auditing


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. 

To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).
