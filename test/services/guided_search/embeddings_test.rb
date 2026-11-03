require "test_helper"

module GuidedSearch
  class EmbeddingsTest < ActiveSupport::TestCase
    test "stub mode returns a normalized vector of the configured dimension" do
      embedder = Embeddings.new(mode: "stub", dimensions: 1024)
      vector = embedder.embed("STEM magnet school")
      assert_equal 1024, vector.length
      assert_in_delta 1.0, Math.sqrt(vector.sum { |v| v * v }), 1e-6
    end

    test "stub mode is deterministic and input-sensitive" do
      embedder = Embeddings.new(mode: "stub", dimensions: 256)
      assert_equal embedder.embed("same"), embedder.embed("same")
      refute_equal embedder.embed("one"), embedder.embed("two")
    end

    test "embed_batch returns one vector per input" do
      vectors = Embeddings.new(mode: "stub", dimensions: 128).embed_batch(%w[a b c])
      assert_equal [128, 128, 128], vectors.map(&:length)
    end

    test "bedrock mode parses the embedding from a stubbed client" do
      vector = Array.new(1024) { 0.01 }
      client = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
      client.stub_responses(:invoke_model,
        body: StringIO.new({ embedding: vector, inputTextTokenCount: 3 }.to_json),
        content_type: "application/json")
      embedder = Embeddings.new(mode: "bedrock", dimensions: 1024, client: client)
      assert_equal vector, embedder.embed("hello")
    end

    test "bedrock mode wraps a wrong-dimension response in UpstreamError" do
      client = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
      client.stub_responses(:invoke_model,
        body: StringIO.new({ embedding: [0.1, 0.2] }.to_json),
        content_type: "application/json")
      embedder = Embeddings.new(mode: "bedrock", dimensions: 1024, client: client)
      assert_raises(GuidedSearch::UpstreamError) { embedder.embed("hello") }
    end

    test "unknown mode raises ArgumentError" do
      assert_raises(ArgumentError) { Embeddings.new(mode: "nope").embed("x") }
    end
  end
end
