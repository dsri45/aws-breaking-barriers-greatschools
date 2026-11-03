require "net/http"
require "uri"

module GuidedSearch
  class OpenSearch
    # Managed Amazon OpenSearch Service is reached over HTTPS with SigV4 (the
    # default). For local development against a Docker node, set OPENSEARCH_URL
    # to an http:// origin: signing is skipped and plain HTTP is used. The
    # managed path is unchanged.
    def initialize(endpoint: ENV.fetch("OPENSEARCH_URL"), open_timeout: 3, read_timeout: 8)
      @endpoint = URI.parse(endpoint)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @local = @endpoint.is_a?(URI::HTTP) && !@endpoint.is_a?(URI::HTTPS)

      valid_origin =
        @endpoint.host && @endpoint.userinfo.nil? &&
        ["", "/"].include?(@endpoint.path) && @endpoint.query.nil? && @endpoint.fragment.nil?

      if @local
        raise ArgumentError, "OPENSEARCH_URL must be a valid origin" unless valid_origin

        return # no signer for local plain-HTTP development
      end

      unless @endpoint.is_a?(URI::HTTPS) && valid_origin
        raise ArgumentError, "OPENSEARCH_URL must be an HTTPS origin"
      end

      @signer = Aws::Sigv4::Signer.new(
        service: "es",
        region: ENV.fetch("AWS_REGION", "us-east-1"),
        credentials_provider: Aws::CredentialProviderChain.new.resolve
      )
    rescue Aws::Sigv4::Errors::MissingCredentialsError => error
      raise UpstreamError, "OpenSearch #{error.class}"
    end

    # Set ndjson: true for the _bulk API, where `body` is an array of objects
    # serialized as newline-delimited JSON (with a trailing newline).
    def request(method, path, body: nil, ndjson: false)
      raise ArgumentError, "Expected an OpenSearch path" unless path.start_with?("/") && !path.start_with?("//")

      uri = @endpoint + path
      payload =
        if body.nil?
          nil
        elsif ndjson
          body.map { |line| line.to_json }.join("\n") + "\n"
        else
          body.to_json
        end
      headers = { "Accept" => "application/json" }
      headers["Content-Type"] = ndjson ? "application/x-ndjson" : "application/json" if payload

      headers = headers.merge(@signer.sign_request(http_method: method, url: uri, headers: headers, body: payload).headers) unless @local

      request = Net::HTTPGenericRequest.new(method, !payload.nil?, method != "HEAD", uri.request_uri, headers)
      request.body = payload if payload

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: !@local,
        open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise UpstreamError, "OpenSearch HTTP #{response.code}"
      end

      JSON.parse(response.body) if response.body.present?
    rescue SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError,
      Aws::Sigv4::Errors::MissingCredentialsError => error
      raise UpstreamError, "OpenSearch #{error.class}"
    end
  end
end
