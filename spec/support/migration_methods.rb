
module MigrationMethods
  # Was running into issues with the advisory locks and the migrations for setting up database
  # So disabled the advisory locks for the migrations
  def with_advisory_locking_disabled
    original_value = ActiveRecord::Base.connection.instance_variable_get(:@advisory_locks_enabled)

    begin
      ActiveRecord::Base.connection.instance_variable_set(:@advisory_locks_enabled, false)
      yield
    ensure
      ActiveRecord::Base.connection.instance_variable_set(:@advisory_locks_enabled, original_value)
    end
  end

  def reset_test_database!
    database_name = ActiveRecord::Base.connection.instance_variable_get('@config')[:database]
    run_sql_commands(["DROP DATABASE IF EXISTS #{database_name}",
                      "CREATE DATABASE #{database_name} DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_unicode_ci",
                      "USE #{database_name}"])

      begin
        # We use the file "base_schema.rb" here so that it is not updated automatically
        # when running migrations
        ENV["SCHEMA"] = File.expand_path("../../dummy/db/base_schema.rb", __FILE__)

        Rake::Task['db:schema:load'].invoke
      rescue StandardError => e
        binding.pry
        puts "there was an error creating your database #{e}"
        raise e
      end
  end

  def conn
    ActiveRecord::Base.connection
  end

  def run_sql_commands(sql)
    conn.execute('START TRANSACTION')
    sql.each { |str| conn.execute(str) }
    conn.execute('COMMIT')
  end

  def run_db_migrate(direction, version)
    original_version = ENV["VERSION"]
    ENV["VERSION"] = version.to_s

    puts "[run_db_migrate] running migration #{version} #{direction}"

    begin
      case direction.to_sym
      when :up
        Rake::Task['db:migrate:up'].invoke
      when :down
         Rake::Task['db:migrate:down'].invoke
      end
    rescue => e
      puts "[run_db_migrate] there was an error running the migration #{e}"
    ensure
      if original_version
        ENV["VERSION"] = original_version
      else
        ENV.delete("VERSION")
      end
    end
  end

  def migrations_current_version
    ActiveRecord::Migrator.current_version
  end

  def migration_paths
    File.expand_path('../dummy/db/migrate/', File.dirname(__FILE__))
  end

  def migration_context
    ActiveRecord::MigrationContext.new(migration_paths, ActiveRecord::SchemaMigration, ActiveRecord::InternalMetadata)
  end

  def migration_fixtures
    migration_context.migrations
  end
end

# This shim is for Rails 7.1 compatibility in the test
module Rails7Compatibility
  module MigrationContext
    def initialize(migrations_paths, schema_migration = nil, internal_metadata = nil)
      super(migrations_paths)
    end
  end
end

if ActiveRecord::VERSION::STRING >= '7.1'
  ActiveRecord::MigrationContext.send :prepend, Rails7Compatibility::MigrationContext
end
