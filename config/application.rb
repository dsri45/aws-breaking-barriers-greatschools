require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module GreatSchools
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[tasks])
    config.filter_parameters += %i[message preferences history]
    config.active_record.schema_format = :ruby
    config.assets.excluded_paths << root.join("app/assets/tailwind")
  end
end
