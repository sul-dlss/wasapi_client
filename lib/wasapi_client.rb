# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/hash/indifferent_access'
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
  # @param base_url [String, nil] the base URL for the WASAPI API'
  def initialize(username:, password:, base_url: nil)
    @username = username
    @password = password
    @base_url = base_url
  end

  NUM_RETRIES = 5

  attr_accessor :username, :password, :base_url

  def default_url
    'https://partner.archive-it.org'
  end

  def default_storage_url
    'https://warcs.archive-it.org/webdatafile/'
  end

  # Set up an authenticated GET request for the account
  def connection(url)
    Faraday.new(url:) do |conn|
      conn.use Faraday::Response::RaiseError
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
  # rubocop:disable Metrics/CyclomaticComplexity
  def fetch_warcs(collection:, output_dir:, crawl_start_after: nil, crawl_start_before: nil)
    locations = get_locations(collection:, crawl_start_after:, crawl_start_before:)
    return nil if locations.empty?

    FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
    locations.each do |location|
      # See if the file already exists and has the correct checksum
      filepath = File.join(output_dir, File.basename(location[:url]))
      next if checksum_valid?(filepath:, expected_md5: location[:md5])

      retries = 0
      until (valid = checksum_valid?(filepath:, expected_md5: location[:md5])) || retries >= NUM_RETRIES
        fetch_file(file: location[:url], output_dir:)
        retries += 1
      end

      raise "Failed to fetch a valid file for #{location[:url]} after #{NUM_RETRIES} retries" unless valid
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # Send a GET request for the URLs for WARCs. Response will be paginated.
  # @param collection [String] the Archive-It collection ID to fetch WARC files for
  # @param crawl_start_after [String] the start date for the crawl in RFC3339 format
  # @param crawl_start_before [String] the end date for the crawl in RFC3339 format
  # @return [Array<Hash>] hashes containing WARC file location (URL) and md5 checksums from the parsed JSON response
  def get_locations(collection:, crawl_start_after: nil, crawl_start_before: nil)
    params = {
      'collection': collection,
      'crawl-start-after': crawl_start_after,
      'crawl-start-before': crawl_start_before
    }

    response = query(params:)
    extract_files(response:, params:)
  end

  # Fetch a specific file from the WASAPI storage location.
  # @param file [String] the URL or filename for the file
  # @param output_dir [String] the directory to save the file to
  # @return [String, nil] the path to the downloaded file, or nil if not found
  def fetch_file(file:, output_dir:, base_url: default_storage_url)
    # Determine if the input is a URL or a filename
    file = URI.join(base_url, file).to_s unless file.start_with?('http')

    download(url: file, output_dir:)
  end

  # Send a GET request for WARCs filenames.
  # @param collection [String] the Archive-It collection ID
  # @param crawl_start_after [String] the start date for the crawl in RFC3339 format
  # @param crawl_start_before [String] the end date for the crawl in RFC3339 format
  # @return [Array<String>] WARC filenames
  def filenames(collection:, crawl_start_after: nil, crawl_start_before: nil)
    locations = get_locations(collection:, crawl_start_after:, crawl_start_before:)
    locations.map { |location| File.basename(location[:url]) }
  end

  private

  # Extract the WARC file locations and checksums from the response while paginating through results
  # @param response [Hash] the parsed JSON response from the WASAPI API
  # @param params [Hash] the parameters used for the request, to support pagination
  # @return [Array<Hash>] hashes containing WARC file location (URL) and md5 checksum
  def extract_files(response:, params:)
    files = response['files']
    return [] unless files.any?

    # use the first (primary) location for each file. The second is a backup which may not be complete when accessed.
    files.map! { |file| { url: file['locations'].first, md5: file&.dig('checksums', 'md5') } }

    while response['next']
      response = query(params:, next_page: response['next'])
      new_files = response['files']
      return [] unless new_files.any?

      files << new_files.map! { |file| { url: file['locations'].first, md5: file&.dig('checksums', 'md5') } }
    end

    files.flatten
  end

  # Send a GET request for WARC files matching the query params
  # @param params [Hash] the parameters for the request, including:
  #   - collection: the collection ID to fetch WARC files for
  #   - crawl-start-after: the start date for the crawl in RFC3339 format
  #   - crawl-start-before: the end date for the crawl in RFC3339 format
  # @param base_url [String] the base URL for the WASAPI API
  # @param next_page [String, nil] the URL for the next page of results, if available
  # @return [Hash] parsed JSON response
  def query(params:, base_url: default_url, next_page: nil)
    # If a next page is provided, use it to fetch the next set of results
    response = if next_page
                 connection(next_page).get
               else
                 connection(base_url).get('/wasapi/v1/webdata', params)
               end

    raise "Failed to get list of WARCS: #{response.status}: #{response.body}" unless response.success?

    return nil unless response.body

    JSON.parse(response.body).with_indifferent_access
  end

  # Download a file and save it to the specified output directory
  # @param url [String] the URL of the file to download
  # @param output_dir [String] the directory to save the downloaded file to
  def download(url:, output_dir:)
    filename = File.basename(URI.parse(url).path)
    filepath = File.join(output_dir, filename)
    File.open(filepath, 'wb') do |file|
      # Use streaming to write the file in chunks. WARCs can be large.
      connection(url).get do |req|
        req.options.on_data = proc do |chunk, _size, env|
          if env.status >= 300
            FileUtils.rm_f(filepath) if File.exist?(filepath)
            raise "Failed to download file from #{url}: #{env.status}"
          end

          file.write(chunk)
        end
      end
    end
    filepath
  end

  # Calculate the MD5 checksum of the downloaded file and verify it against the expected checksum
  def checksum_valid?(filepath:, expected_md5:)
    raise "No md5 checksum provided for #{File.basename(filepath)}" unless expected_md5
    return false unless File.exist?(filepath)

    actual_md5 = Digest::MD5.file(filepath).hexdigest
    actual_md5 == expected_md5
  end
end
