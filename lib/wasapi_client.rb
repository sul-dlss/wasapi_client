# frozen_string_literal: true

require 'active_support/core_ext/object'
require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/retry'
require 'singleton'
require 'zeitwerk'

# Load the gem's internal dependencies: use Zeitwerk instead of needing to manually require classes
Zeitwerk::Loader.for_gem.setup

# Client for interacting with the Archive-It WASAPI APIs
# WasapiClient.new(username: 'username', password: 'password').fetch_warcs(
#   output_dir: 'path/to/save/warcs',
#   collection: '12345',
#   crawl_start_after: '2023-01-01',
#   crawl_start_before: '2023-01-31'
# )
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class WasapiClient
  # @param username [String] the Archive-It account username
  # @param password [String] the Archive-It account password
  def initialize(username:, password:)
    @username = username
    @password = password
  end

  attr_accessor :username, :password

  def default_url
    'https://partner.archive-it.org'
  end

  # Set up an authenticated GET request for the account
  def connection(url)
    Faraday.new(url:) do |conn|
      conn.request :authorization, :basic, username, password
      conn.request :retry, max: 3, interval: 0.05, backoff_factor: 2
      conn.response :follow_redirects
    end
  end

  # Send a GET request for the URLs for WARCs. Response will be paginated.
  # @param collection [String] the collection ID to fetch WARC files for
  # @param crawl_start_after [String] the start date for the crawl in RFC3339 format
  # @param crawl_start_before [String] the end date for the crawl in RFC3339 format
  # @return [Array] the WARC URIs from the parsed JSON response
  def get_locations(collection:, crawl_start_after:, crawl_start_before:)
    params = {
      'collection': collection,
      'crawl-start-after': crawl_start_after,
      'crawl-start-before': crawl_start_before,
      'page': '1'
    }

    response = query(params)
    files = response['files']
    return [] unless files.any?

    files.map! { |file| file['locations'].first }

    while response['next']
      params['page'] = response['next']
      response = query(params)
      new_files = response['files']
      return [] unless new_files.any?

      files << new_files.map! { |file| file['locations'].first }
    end

    files.flatten
  end

  # Send a GET request for WARC files matching the query params
  # @param params [Hash] the parameters for the request, including:
  #   - collection: the collection ID to fetch WARC files for
  #   - crawl-start-after: the start date for the crawl in RFC3339 format
  #   - crawl-start-before: the end date for the crawl in RFC3339 format
  # @return [Hash] parsed JSON response
  def query(params)
    response = connection(default_url).get('/wasapi/v1/webdata', params)
    raise "Failed to get list of WARCS: #{response.status}: #{response.body}" unless response.success?

    return nil unless response.body.present?

    JSON.parse(response.body)
  end

  # Send a GET request for the URLs for WARCs. Response will be paginated.
  # @param collection [String] the collection ID to fetch WARC files for
  # @output_dir [String] the directory to save the WARC files to
  # @param crawl_start_after [String] the start date for the crawl in RFC3339 format
  # @param crawl_start_before [String] the end date for the crawl in RFC3339 format
  def fetch_warcs(collection:, output_dir:, crawl_start_after: nil, crawl_start_before: nil)
    locations = get_locations(collection:, crawl_start_after:, crawl_start_before:)

    return nil if locations.empty?

    FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
    locations.each do |url|
      filename = File.basename(URI.parse(url).path)
      filepath = File.join(output_dir, filename)
      File.open(filepath, 'wb') do |file|
        # Use streaming to write the file in chunks
        connection(url).get do |req|
          req.options.on_data = proc { |chunk, _| file.write(chunk) }
        end
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
