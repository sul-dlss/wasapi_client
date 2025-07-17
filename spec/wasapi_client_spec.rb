# frozen_string_literal: true

RSpec.describe WasapiClient do
  subject(:client) { described_class.new(username: 'username', password: 'password') }

  let(:collection_id) { '12345' }
  let(:crawl_start_after) { '2023-01-01' }
  let(:crawl_start_before) { '2023-01-31' }
  let(:response_body) do
    {
      'count' => 2,
      'next' => nil,
      'previous' => nil,
      'files' => [
        { 'filename' => 'warc1.warc.gz',
          'checksums' => { 'md5' => md5_mock },
          'locations' => ['https://example.com/warc1.warc.gz', 'https://backup.example.com/warc1.warc.gz'],
          'crawl-time' => '2017-03-07T20:01:32Z',
          'crawl-start' => '2017-03-07T20:01:18Z',
          'store-time' => '2017-03-08T23:25:41Z' },
        { 'filename' => 'warc2.warc.gz',
          'checksums' => { 'md5' => md5_mock },
          'locations' => ['https://example.com/warc2.warc.gz', 'https://backup.example.com/warc2.warc.gz'],
          'crawl-time' => '2017-03-07T20:01:32Z',
          'crawl-start' => '2017-03-07T20:01:18Z',
          'store-time' => '2017-03-08T23:25:41Z' }
      ]
    }
  end
  let(:md5_mock) { 'md5' }

  before do
    stub_request(:get, "#{client.default_url}/wasapi/v1/webdata")
      .with(query: {
              'collection': collection_id,
              'crawl-start-after': crawl_start_after,
              'crawl-start-before': crawl_start_before
            })
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
    allow(Digest::MD5).to receive(:file).and_return(instance_double(Digest::MD5, hexdigest: md5_mock))
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
                                { url: 'https://example.com/warc1.warc.gz',
                                  md5: 'md5' },
                                { url: 'https://example.com/warc2.warc.gz',
                                  md5: 'md5' }
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
      locations.each do |location|
        stub_request(:get, location)
          .to_return(status: 200, body: "fake content for #{File.basename(location)}")
      end
    end

    after do
      FileUtils.remove_entry(output_dir)
    end

    context 'when downloading for the first time' do
      let(:filepath) { File.join(output_dir, 'warc1.warc.gz') }
      let(:filepath2) { File.join(output_dir, 'warc2.warc.gz') }

      before do
        FileUtils.mkdir_p(output_dir)
        allow(Digest::MD5).to receive(:file).with(filepath).and_return(instance_double(Digest::MD5,
                                                                                       hexdigest: md5_mock))
        allow(Digest::MD5).to receive(:file).with(filepath2).and_return(instance_double(Digest::MD5,
                                                                                        hexdigest: md5_mock))
      end

      it 'downloads WARC files to the specified directory' do
        expect do
          client.fetch_warcs(
            collection: collection_id,
            crawl_start_after: crawl_start_after,
            crawl_start_before: crawl_start_before,
            output_dir: output_dir
          )
        end.not_to raise_error

        expect(Dir.entries(output_dir).select { |f| f.end_with?('.gz') })
          .to match_array(['warc1.warc.gz', 'warc2.warc.gz'])
      end
    end

    context 'when paginated response is returned' do
      let(:response_body) do
        {
          'count' => 2,
          'next' => 'https://example.com/wasapi/v1/webdata?page=2',
          'previous' => nil,
          'files' => [
            { 'filename' => 'warc1.warc.gz',
              'checksums' => { 'md5' => md5_mock },
              'locations' => ['https://example.com/warc1.warc.gz', 'https://backup.example.com/warc1.warc.gz'],
              'crawl-time' => '2017-03-07T20:01:32Z',
              'crawl-start' => '2017-03-07T20:01:18Z',
              'store-time' => '2017-03-08T23:25:41Z' }
          ]
        }
      end
      let(:response_body_page2) do
        {
          'count' => 2,
          'next' => nil,
          'previous' => 'https://example.com/wasapi/v1/webdata?page=1',
          'files' => [
            { 'filename' => 'warc2.warc.gz',
              'checksums' => { 'md5' => md5_mock },
              'locations' => ['https://example.com/warc2.warc.gz', 'https://backup.example.com/warc2.warc.gz'],
              'crawl-time' => '2017-03-07T20:01:32Z',
              'crawl-start' => '2017-03-07T20:01:18Z',
              'store-time' => '2017-03-08T23:25:41Z' }
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
        stub_request(:get, 'https://example.com/wasapi/v1/webdata?page=2')
          .to_return(status: 200, body: response_body_page2.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'fetches all WARC files across paginated responses' do
        expect do
          client.fetch_warcs(
            collection: collection_id,
            crawl_start_after: crawl_start_after,
            crawl_start_before: crawl_start_before,
            output_dir: output_dir
          )
        end.not_to raise_error

        expect(Dir.entries(output_dir).select { |f| f.end_with?('.gz') })
          .to match_array(['warc1.warc.gz', 'warc2.warc.gz'])
      end
    end

    context 'when full file already exists' do
      let(:response_body) do
        {
          'count' => 2,
          'next' => nil,
          'previous' => nil,
          'files' => [
            { 'filename' => 'warc1.warc.gz',
              'checksums' => { 'md5' => md5_mock },
              'locations' => ['https://example.com/warc1.warc.gz', 'https://backup.example.com/warc1.warc.gz'],
              'crawl-time' => '2017-03-07T20:01:32Z',
              'crawl-start' => '2017-03-07T20:01:18Z',
              'store-time' => '2017-03-08T23:25:41Z' }
          ]
        }
      end

      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'warc1.warc.gz'), 'existing content for warc1.warc.gz')
        stub_request(:get, "#{client.default_url}/wasapi/v1/webdata")
          .with(query: {
                  'collection': collection_id,
                  'crawl-start-after': crawl_start_after,
                  'crawl-start-before': crawl_start_before
                })
          .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
        allow(Digest::MD5).to receive(:file).and_return(instance_double(Digest::MD5, hexdigest: 'md5'))
        allow(client).to receive(:download).and_call_original
      end

      it 'does not download the file again' do
        expect do
          client.fetch_warcs(
            collection: collection_id,
            crawl_start_after: crawl_start_after,
            crawl_start_before: crawl_start_before,
            output_dir: output_dir
          )
        end.not_to raise_error
        expect(client).not_to have_received(:download)
      end
    end

    context 'when file does not have valid checksum' do
      before do
        allow(Digest::MD5).to receive(:file).and_return(instance_double(Digest::MD5, hexdigest: 'invalid checksum'))
      end

      it 'raises an error' do
        expect do
          client.fetch_warcs(
            collection: collection_id,
            crawl_start_after: crawl_start_after,
            crawl_start_before: crawl_start_before,
            output_dir: output_dir
          )
        end.to raise_error(RuntimeError,
                           'Failed to fetch a valid file for https://example.com/warc1.warc.gz after 5 retries')
      end
    end

    context 'when WASAPI response lacks md5 checksums' do
      let(:response_body) do
        {
          "count": 1,
          "next": nil,
          "previous": nil,
          'files' => [
            { 'filename' => 'warc1.warc.gz',
              'locations' => ['https://example.com/warc1.warc.gz', 'https://backup.example.com/warc1.warc.gz'],
              'checksums' => { sha1: 'sha1' },
              'crawl-time': '2017-03-07T20:01:32Z',
              'crawl-start': '2017-03-07T20:01:18Z',
              'store-time': '2017-03-08T23:25:41Z' }
          ]
        }
      end
      before do
        stub_request(:get, "#{client.default_url}/wasapi/v1/webdata")
          .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises an error' do
        expect do
          client.fetch_warcs(
            collection: collection_id,
            crawl_start_after: crawl_start_after,
            crawl_start_before: crawl_start_before,
            output_dir: output_dir
          )
        end.to raise_error(RuntimeError, 'No md5 checksum provided for warc1.warc.gz')
      end
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

    context 'when file is not found' do
      let(:file) { 'https://example.com/bogus.warc.gz' }

      before do
        stub_request(:get, file)
          .to_return(status: 404, body: 'Not Found')
      end

      after do
        FileUtils.remove_entry(output_dir)
      end

      it 'raises an error when the file is not found' do
        expect do
          client.fetch_file(file:, output_dir: output_dir)
        end.to raise_error(RuntimeError, "Failed to download file from #{file}: 404")
        expect(File.exist?(File.join(output_dir, 'bogus.warc.gz'))).to be false
      end
    end
  end

  describe '.filenames' do
    it 'returns filenames for a collection and date range' do
      filenames = client.filenames(
        collection: collection_id,
        crawl_start_after: crawl_start_after,
        crawl_start_before: crawl_start_before
      )

      expect(filenames).to eq(['warc1.warc.gz', 'warc2.warc.gz'])
    end
  end
end
