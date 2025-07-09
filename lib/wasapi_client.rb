# frozen_string_literal: true

require 'active_support'
require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/retry'
require 'zeitwerk'

# Load the gem's internal dependencies: use Zeitwerk instead of needing to manually require classes
Zeitwerk::Loader.for_gem.setup

# Client for interacting with the Archive-It WASAPI APIs
class WasapiClient
  # @param username [String] an Archive-It account username
  # @param password [String] an Archive-It account password
  def initialize(username:, password:, base_url: nil)
    @username = username
    @password = password
    @base_url = base_url
  end

  attr_accessor :username, :password, :base_url

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

  # Send a GET request for the URLs for WARCs and download files. Response will be paginated.
  # @param collection [String] the collection ID to fetch WARC files for
  # @param output_dir [String] the directory to save the WARC files to
  # @param crawl_start_after [String] the start date for the crawl in RFC3339 format
  # @param crawl_start_before [String] the end date for the crawl in RFC3339 format
  def fetch_warcs(collection:, output_dir:, crawl_start_after: nil, crawl_start_before: nil)
    locations = get_locations(collection:, crawl_start_after:, crawl_start_before:)

    return nil if locations.empty?

    FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
    locations.each do |url|
      fetch_file(url:, output_dir:)
    end
  end

  # Fetch a specific file by URL from the collection's WARC locations
  # @param collection [String] the Archive-It collection ID to fetch the file from
  # @param url [String] the URL for the file
  # @param output_dir [String] the directory to save the file to
  # @return [String, nil] the path to the downloaded file, or nil if not found
  def fetch_file(url:, output_dir:)
    filepath = File.join(output_dir, File.basename(URI.parse(url).path))
    FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

    download_by_url(url:, output_dir:)

    raise "Failed to download file from #{url} to #{filepath}" unless File.exist?(filepath)

    filepath
  end

  # Send a GET request for the URLs for WARCs. Response will be paginated.
  # @param collection [String] the Archive-It collection ID to fetch WARC files for
  # @param crawl_start_after [String] the start date for the crawl in RFC3339 format
  # @param crawl_start_before [String] the end date for the crawl in RFC3339 format
  # @return [Array] the WARC URLs from the parsed JSON response
  def get_locations(collection:, crawl_start_after: nil, crawl_start_before: nil)
    params = {
      'collection': collection,
      'crawl-start-after': crawl_start_after,
      'crawl-start-before': crawl_start_before
    }

    response = query(params:)
    extract_file_urls(response)
  end

  private

  # Extract the WARC file locations from the response while paginating through results
  # @param response [Hash] the parsed JSON response from the WASAPI API
  # @return [Array] an array of WARC file locations (URLs)
  def extract_files(response)
    files = response['files']
    return [] unless files.any?

    # use the first (primary) location for each file. The second is a backup which may not be complete when accessed.
    files.map! { |file| file['locations'].first }

    while response['next']
      params['page'] = response['next']
      response = query(params:)
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
  # @param base_url [String] the base URL for the WASAPI API
  # @return [Hash] parsed JSON response
  def query(params:, base_url: default_url)
    response = connection(base_url).get('/wasapi/v1/webdata', params)
    raise "Failed to get list of WARCS: #{response.status}: #{response.body}" unless response.success?

    return nil unless response.body

    JSON.parse(response.body)
  end

  # Download a file from a given URL and save it to the specified output directory
  # @param url [String] the URL of the file to download
  # @param output_dir [String] the directory to save the downloaded file to
  def download_by_url(url:, output_dir:)
    filename = File.basename(URI.parse(url).path)
    filepath = File.join(output_dir, filename)
    File.open(filepath, 'wb') do |file|
      # Use streaming to write the file in chunks. WARCs can be large.
      connection(url).get do |req|
        req.options.on_data = proc { |chunk, _| file.write(chunk) }
      end
    end
  end

  # Download file by filename from the default WARC storage location.
  # Used in audit and remediation where only the filename is available.
  # @param filename [String] the name of the file to download
  # @param output_dir [String] the directory to save the file to
  # @param base_url [String] the base URL for WARC storage location
  def download_by_filename(filename:, output_dir:, base_url: nil)
    download_base = base_url || 'https://warcs.archive-it.org/webdatafile/'
    url = URI.join(download_base, filename).to_s
    download_by_url(url:, output_dir:)
  end
end
