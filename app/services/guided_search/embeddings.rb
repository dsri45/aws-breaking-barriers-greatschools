require "digest"

module GuidedSearch
  # Produces text embeddings for hybrid search: Amazon Titan Text Embeddings V2
  # (1024 dims) via Bedrock invoke_model. Mirrors GuidedSearch::Bedrock's
  # conventions (shared client options, UpstreamError wrapping).
  #
  # Mode is chosen by EMBEDDINGS_MODE:
  #   "bedrock" -> real Titan call (needs AWS creds + model access)
  #   "stub"    -> deterministic local pseudo-vectors (no AWS; dev/tests/load)
  #
  # Both modes return L2-normalized Float vectors of EMBEDDINGS_DIMENSIONS
  # length, matching the knn_vector mapping (cosinesimil).
  class Embeddings
    DEFAULT_MODEL_ID = "amazon.titan-embed-text-v2:0"
    DEFAULT_DIMENSIONS = 1024

    attr_reader :mode, :dimensions, :model_id

    def initialize(
      mode: ENV.fetch("EMBEDDINGS_MODE", "stub"),
      model_id: ENV.fetch("EMBEDDINGS_MODEL_ID", DEFAULT_MODEL_ID),
      dimensions: ENV.fetch("EMBEDDINGS_DIMENSIONS", DEFAULT_DIMENSIONS).to_i,
      client: nil
    )
      @mode = mode.to_s
      @model_id = model_id
      @dimensions = dimensions
      @client = client
    end

    # @param text [String]
    # @return [Array<Float>] normalized vector of `dimensions` length
    def embed(text)
      case mode
      when "bedrock" then bedrock_embed(text.to_s)
      when "stub"    then stub_embed(text.to_s)
      else raise ArgumentError, "Unknown EMBEDDINGS_MODE=#{mode.inspect} (expected 'bedrock' or 'stub')"
      end
    end

    # Titan's invoke_model is single-input; this iterates so the loader has one
    # batching seam to tune later.
    # @param texts [Array<String>]
    # @return [Array<Array<Float>>]
    def embed_batch(texts)
      texts.map { |text| embed(text) }
    end

    private

    def client
      @client ||= Aws::BedrockRuntime::Client.new(
        region: ENV.fetch("AWS_REGION", "us-east-1"),
        http_open_timeout: 3,
        http_read_timeout: 25,
        retry_limit: 1
      )
    end

    def bedrock_embed(text)
      response = client.invoke_model(
        model_id: model_id,
        content_type: "application/json",
        accept: "application/json",
        body: { inputText: text, dimensions: dimensions, normalize: true }.to_json
      )
      vector = JSON.parse(response.body.read)["embedding"]
      unless vector.is_a?(Array) && vector.length == dimensions
        raise UpstreamError, "Embeddings Titan returned unexpected shape (expected #{dimensions})"
      end

      vector
    rescue Aws::BedrockRuntime::Errors::ServiceError, Aws::Errors::MissingCredentialsError,
      Seahorse::Client::NetworkingError, JSON::ParserError => error
      raise UpstreamError, "Embeddings #{error.class}"
    end

    # Deterministic pseudo-embedding seeded from a digest of the text, so the
    # same text always yields the same normalized vector. Not semantically
    # meaningful, but stable and correctly shaped for loading and tests.
    def stub_embed(text)
      rng = Random.new(Digest::SHA256.hexdigest(text)[0, 16].to_i(16))
      normalize(Array.new(dimensions) { rng.rand(-1.0..1.0) })
    end

    def normalize(vector)
      magnitude = Math.sqrt(vector.sum { |value| value * value })
      return vector if magnitude.zero?

      vector.map { |value| value / magnitude }
    end
  end
end
