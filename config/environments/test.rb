Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = true
  config.action_dispatch.show_exceptions = :rescuable
  config.cache_store = :memory_store
  config.active_support.deprecation = :stderr
end
