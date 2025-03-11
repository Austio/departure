require 'bundler'
require 'simplecov'
SimpleCov.start

require 'bundler/setup'
require 'departure'
require 'rails'
require 'rake'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

# Load Dummy Application - schema.rb holds the schema for the test database
RAILS_ENV = 'test'
require File.expand_path('./dummy/config/environment.rb', __dir__)
require 'rspec/rails'

require 'lhm'


# Require all support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }
Rails.application.load_tasks

RSpec.configure do |config|
  config.include TableMethods
  config.include MigrationMethods
  config.filter_run_when_matching :focus

  ActiveRecord::Migration.verbose = true

  # Needs an empty block to initialize the config with the default values
  Departure.configure do |_config|
  end

  # Cleans up the database before each example, so the current example doesn't
  # see the state of the previous one
  config.before(:each) do |example|
    if example.metadata[:integration]

    end
  end

  # We manually reset the db each time
  config.use_transactional_fixtures = false

  config.order = :random

  Kernel.srand config.seed
end
