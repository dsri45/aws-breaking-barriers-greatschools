ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Load shared test support (e.g. OpenSearch integration helpers).
Dir[Rails.root.join("test/support/**/*.rb")].each { |file| require file }

class ActiveSupport::TestCase
  setup { Rails.cache.clear }
end
