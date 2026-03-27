Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.enable_reloading = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.seconds.to_i}"
  }

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = :none

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false
  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  config.action_mailer.delivery_method = :test

  config.active_support.report_deprecations = true

  config.secret_key_base = '54c76bda862861241cf840ccdb3df54df3ff693617eb05ba91224d60a175619c1709a9ff49702545dbb602a36ba184a6aac61b9246b237d531c0d86dad15be06'
end
