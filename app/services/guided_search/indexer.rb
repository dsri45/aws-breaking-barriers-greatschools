module GuidedSearch
  # Creates and drops the schools and programs indexes from the mapping JSON in
  # config/opensearch/, over GuidedSearch::OpenSearch's raw REST interface.
  # All operations are idempotent.
  class Indexer
    INDEXES = {
      "schools"  => "schools_index.json",
      "programs" => "programs_index.json"
    }.freeze

    def initialize(client: GuidedSearch::OpenSearch.new)
      @client = client
    end

    def create_all
      INDEXES.keys.select { |name| create(name) }
    end

    def drop_all
      INDEXES.keys.select { |name| drop(name) }
    end

    def recreate_all
      drop_all
      create_all
    end

    # @return [Boolean] true if created, false if it already existed
    def create(name)
      return false if exists?(name)

      @client.request("PUT", "/#{name}", body: mapping_for(name))
      true
    end

    # @return [Boolean] true if dropped, false if it did not exist
    def drop(name)
      return false unless exists?(name)

      @client.request("DELETE", "/#{name}")
      true
    end

    def exists?(name)
      @client.request("GET", "/#{name}")
      true
    rescue GuidedSearch::UpstreamError
      false
    end

    def mapping(name)
      @client.request("GET", "/#{name}/_mapping")
    end

    def count(name)
      @client.request("GET", "/#{name}/_count")&.fetch("count", 0)
    rescue GuidedSearch::UpstreamError
      0
    end

    private

    def mapping_for(name)
      file = INDEXES.fetch(name) { raise ArgumentError, "Unknown index '#{name}'" }
      JSON.parse(File.read(Rails.root.join("config", "opensearch", file)))
    end
  end
end
