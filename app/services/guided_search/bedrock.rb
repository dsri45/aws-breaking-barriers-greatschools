module GuidedSearch
  class Bedrock
    def initialize(client: Aws::BedrockRuntime::Client.new(
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      http_open_timeout: 3,
      http_read_timeout: 25,
      retry_limit: 0
    ))
      @client = client
    end

    def converse(messages:, system: [], inference_config: {})
      @client.converse(
        model_id: ENV.fetch("BEDROCK_MODEL_ID", "amazon.nova-pro-v1:0"),
        messages: messages,
        system: system,
        inference_config: inference_config
      )
    rescue Aws::BedrockRuntime::Errors::ServiceError, Aws::Errors::MissingCredentialsError,
      Seahorse::Client::NetworkingError => error
      raise UpstreamError, "Bedrock #{error.class}"
    end
  end
end
