RAILS_ENV = "test"

require 'simplecov'
SimpleCov.start
require 'pry'
require 'bundler/setup'
require 'rails'
require 'rake'
require 'departure'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

# Load Dummy Application - schema.rb holds the schema for the test database
require File.expand_path('./dummy/config/boot.rb', __dir__)
require File.expand_path('./dummy/config/environment.rb', __dir__)

require 'lhm'


# Require all support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }
Rails.application.load_tasks

Rake::Task['db:create'].invoke

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
      reset_test_database!
    end
  end

  # We manually reset the db each time
  # config.use_transactional_fixtures = false

  config.order = :random

  Kernel.srand config.seed
end

# This shim is for Rails 7.1 compatibility in the test
# module Rails7Compatibility
#   module MigrationContext
#     def initialize(migrations_paths, schema_migration = nil, internal_metadata = nil)
#       super(migrations_paths)
#     end
#   end
# end
#
# if ActiveRecord::VERSION::STRING >= '7.1'
#   ActiveRecord::MigrationContext.send :prepend, Rails7Compatibility::MigrationContext
# end
