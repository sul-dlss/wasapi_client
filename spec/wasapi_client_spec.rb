# frozen_string_literal: true

RSpec.describe WasapiClient do
  subject(:client) { described_class.new(username: 'username', password: 'password') }

  let(:collection_id) { '12345' }
  let(:crawl_start_after) { '2023-01-01' }
  let(:crawl_start_before) { '2023-01-31' }
  let(:response_body) do
    {
      "count": 2,
      "next": nil,
      "previous": nil,
      'files' => [
        { 'filename' => 'warc1.warc.gz',
          'locations' => ['https://example.com/warc1.warc.gz', 'https://backup.example.com/warc1.warc.gz'],
          "crawl-time": '2017-03-07T20:01:32Z',
          "crawl-start": '2017-03-07T20:01:18Z',
          "store-time": '2017-03-08T23:25:41Z' },
        { 'filename' => 'warc2.warc.gz',
          'locations' => ['https://example.com/warc2.warc.gz', 'https://backup.example.com/warc2.warc.gz'],
          "crawl-time": '2017-03-07T20:01:32Z',
          "crawl-start": '2017-03-07T20:01:18Z',
          "store-time": '2017-03-08T23:25:41Z' }
      ]
    }
  end

  before do
    stub_request(:get, "#{client.default_url}/wasapi/v1/webdata")
      .with(query: {
              'collection': collection_id,
              'crawl-start-after': crawl_start_after,
              'crawl-start-before': crawl_start_before
            })
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'version' do
    it 'returns the correct version' do
      expect(WasapiClient::VERSION).to_not be_nil
    end
  end

  describe '.get_locations' do
    it 'fetches WARC locations for a given collection and date range' do
      locations = client.get_locations(
        collection: collection_id,
        crawl_start_after: crawl_start_after,
        crawl_start_before: crawl_start_before
      )

      expect(locations).to eq([
                                'https://example.com/warc1.warc.gz',
                                'https://example.com/warc2.warc.gz'
                              ])
    end
  end

  describe '.fetch_warcs' do
    let(:output_dir) { Dir.mktmpdir }
    let(:locations) do
      [
        'https://example.com/warc1.warc.gz',
        'https://example.com/warc2.warc.gz'
      ]
    end

    before do
      # stub download requests
      locations.each do |url|
        stub_request(:get, url)
          .to_return(status: 200, body: "fake content for #{File.basename(url)}")
      end
    end

    after do
      FileUtils.remove_entry(output_dir)
    end

    it 'downloads WARC files to the specified directory' do
      client.fetch_warcs(
        collection: collection_id,
        crawl_start_after: crawl_start_after,
        crawl_start_before: crawl_start_before,
        output_dir: output_dir
      )

      expect(Dir.entries(output_dir).select { |f| f.end_with?('.gz') })
        .to match_array(['warc1.warc.gz', 'warc2.warc.gz'])
    end
  end

  describe '.fetch_file' do
    let(:output_dir) { Dir.mktmpdir }

    context 'when file is a URL' do
      let(:file) { 'https://example.com/warc1.warc.gz' }

      before do
        stub_request(:get, file)
          .to_return(status: 200, body: 'fake content for warc1.warc.gz')
      end

      after do
        FileUtils.remove_entry(output_dir)
      end

      it 'downloads a specific file by URL' do
        filepath = client.fetch_file(file:, output_dir: output_dir)

        expect(filepath).to eq(File.join(output_dir, 'warc1.warc.gz'))
        expect(File.exist?(filepath)).to be true
      end
    end

    context 'when file is a filename' do
      let(:file) { 'warc1.warc.gz' }

      before do
        stub_request(:get, 'https://example.com/warc1.warc.gz')
          .to_return(status: 200, body: 'fake content for warc1.warc.gz')
      end

      after do
        FileUtils.remove_entry(output_dir)
      end

      it 'downloads a specific file by filename' do
        filepath = client.fetch_file(file:, output_dir: output_dir, base_url: 'https://example.com/')

        expect(filepath).to eq(File.join(output_dir, 'warc1.warc.gz'))
        expect(File.exist?(filepath)).to be true
      end
    end
  end
end
