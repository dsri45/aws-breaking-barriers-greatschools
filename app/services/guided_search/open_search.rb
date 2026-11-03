require "net/http"
require "uri"

module GuidedSearch
  class OpenSearch
    def initialize(endpoint: ENV.fetch("OPENSEARCH_URL"))
      @endpoint = URI.parse(endpoint)
      unless @endpoint.is_a?(URI::HTTPS) && @endpoint.host && @endpoint.userinfo.nil? &&
          ["", "/"].include?(@endpoint.path) && @endpoint.query.nil? && @endpoint.fragment.nil?
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

    def request(method, path, body: nil)
      raise ArgumentError, "Expected an OpenSearch path" unless path.start_with?("/") && !path.start_with?("//")

      uri = @endpoint + path
      payload = body&.to_json
      headers = { "Accept" => "application/json" }
      headers["Content-Type"] = "application/json" if payload
      signature = @signer.sign_request(http_method: method, url: uri, headers: headers, body: payload)
      request = Net::HTTPGenericRequest.new(method, !payload.nil?, method != "HEAD", uri.request_uri,
        headers.merge(signature.headers))
      request.body = payload if payload

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 8) do |http|
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
