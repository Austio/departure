# frozen_string_literal: true

require_relative 'boot'

require 'active_record/railtie'

require 'departure'
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
  end
end
