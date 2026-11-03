Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = true
  config.assume_ssl = true # CloudFront terminates viewer TLS before the private ALB.
  config.hosts = [/\Ad[a-z0-9]+\.cloudfront\.net\z/]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
  config.cache_store = :memory_store
end
