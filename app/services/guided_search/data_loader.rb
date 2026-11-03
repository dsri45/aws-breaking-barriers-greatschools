module GuidedSearch
  # Loads the sample JSON into the schools and programs indexes.
  #
  # Routing is by SOURCE FILE: db/seeds/school_data.json -> schools,
  # db/seeds/program_data.json -> programs. (Program documents carry no
  # document_type field.)
  #
  # For each document the loader:
  #   * converts the "lat, lon" string in `latlon` into a geo_point `location`
  #   * builds searchable text and attaches its embedding as `embedding`
  #   * indexes using the document's string `id` as the OpenSearch _id
  #
  # Absent keys are preserved: the loader never backfills missing fields, so a
  # school with no summary_rating is indexed without one and the agent can
  # honestly report "no rating published".
  class DataLoader
    SEEDS_DIR = "db/seeds".freeze
    SCHOOL_FILE = "school_data.json".freeze
    PROGRAM_FILE = "program_data.json".freeze
    BULK_BATCH_SIZE = 50

    def initialize(client: GuidedSearch::OpenSearch.new, embeddings: GuidedSearch::Embeddings.new, logger: Rails.logger)
      @client = client
      @embeddings = embeddings
      @logger = logger
    end

    def load_all(school_path: nil, program_path: nil)
      {
        "schools"  => load_schools(path: school_path),
        "programs" => load_programs(path: program_path)
      }
    end

    def load_schools(path: nil)
      docs = read_json(path || seed_path(SCHOOL_FILE))
      bulk_index("schools", docs.map { |doc| prepare_school(doc) })
    end

    def load_programs(path: nil)
      docs = read_json(path || seed_path(PROGRAM_FILE))
      bulk_index("programs", docs.map { |doc| prepare_program(doc) })
    end

    private

    def prepare_school(doc)
      doc = doc.dup
      add_geo_point!(doc)
      doc["embedding"] = @embeddings.embed(school_search_text(doc))
      doc
    end

    def prepare_program(doc)
      doc = doc.dup
      add_geo_point!(doc)
      if doc["organizations"].is_a?(Array)
        doc["organizations"] = doc["organizations"].map do |org|
          org = org.dup
          add_geo_point!(org)
          org
        end
      end
      doc["embedding"] = @embeddings.embed(program_search_text(doc))
      doc
    end

    # Convert "lat, lon" into geo_point { "lat" =>, "lon" => }. No-op if the
    # field is absent or malformed.
    def add_geo_point!(hash)
      raw = hash["latlon"]
      return if raw.nil? || raw.to_s.strip.empty?

      lat, lon = raw.to_s.split(",").map { |part| Float(part.strip) rescue nil }
      hash["location"] = { "lat" => lat, "lon" => lon } if lat && lon
    end

    def school_search_text(doc)
      parts = [doc["name"], doc["esp_text"]]
      parts << "City: #{doc['city']}, #{doc['state']}" if doc["city"]
      parts << "Grades: #{Array(doc['level_codes']).join(', ')}" if doc["level_codes"]
      parts << "Type: #{doc['entity_type']}" if doc["entity_type"]
      parts.concat(Array(doc["ap_courses"]).map { |course| "AP #{course}" }) if doc["ap_courses"]
      parts.concat(Array(doc["reviews_positive"])) if doc["reviews_positive"]
      parts.concat(Array(doc["reviews_negative"])) if doc["reviews_negative"]
      parts.concat(Array(doc["reviews_text"])) if doc["reviews_text"]
      compact_text(parts)
    end

    def program_search_text(doc)
      parts = [doc["name"], doc["description"]]
      parts << "Type: #{doc['program_type']}" if doc["program_type"]
      parts.concat(Array(doc["tag_names"])) if doc["tag_names"]
      parts << "Ages #{doc['age_display']}" if doc["age_display"]
      parts << "City: #{doc['city']}, #{doc['state']}" if doc["city"]
      compact_text(parts)
    end

    def compact_text(parts)
      text = parts.flatten.compact.map(&:to_s).reject(&:empty?).join(". ")
      text.empty? ? "(no description)" : text
    end

    def bulk_index(index, docs)
      indexed = 0
      docs.each_slice(BULK_BATCH_SIZE) do |batch|
        ndjson = batch.flat_map do |doc|
          id = doc.fetch("id") { raise ArgumentError, "document missing 'id'" }
          [{ index: { _index: index, _id: id } }, doc]
        end
        response = @client.request("POST", "/#{index}/_bulk?refresh=true", body: ndjson, ndjson: true)
        check_bulk_errors!(index, response)
        indexed += batch.size
      end
      @logger.info("[data:load] indexed #{indexed} docs into '#{index}'")
      indexed
    end

    def check_bulk_errors!(index, response)
      return unless response && response["errors"]

      failed = response.fetch("items", []).select { |item| item.values.first["error"] }
      raise "Bulk indexing into '#{index}' had #{failed.size} error(s); first: #{failed.first.inspect[0, 500]}"
    end

    def read_json(path)
      raise ArgumentError, "data file not found: #{path}" unless File.exist?(path)

      data = JSON.parse(File.read(path))
      raise ArgumentError, "expected a JSON array in #{path}" unless data.is_a?(Array)

      data
    end

    def seed_path(file)
      Rails.root.join(SEEDS_DIR, file)
    end
  end
end
