
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

  def reset_database!
    with_advisory_locking_disabled do
      Rake::Task['db:drop'].invoke
      begin
        Rake::Task['db:create'].invoke
        Rake::Task['db:schema:load'].invoke
      rescue StandardError => e
        puts "there was an error creating your database #{e}"
        exit 1
      end
    end
  end

  def run_db_migrate(direction, version)
    with_advisory_locking_disabled do
      ActiveRecord::Tasks::DatabaseTasks.migration_connection.migration_context.run(direction.to_sym, version)
    end
  end
end


