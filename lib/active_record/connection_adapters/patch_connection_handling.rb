# frozen_string_literal: true
require "active_record/connection_handling"

module ActiveRecord
  module ConnectionHandling
    # Establishes a connection to the database that's used by all Active
    # Record objects.
    def percona_connection(config)
      if config[:username].nil?
        config = config.dup if config.frozen?
        config[:username] = 'root'
      end
      mysql2_connection = mysql2_connection(config)

      connection_details = Departure::ConnectionDetails.new(config)
      verbose = ActiveRecord::Migration.verbose
      sanitizers = [
        Departure::LogSanitizers::PasswordSanitizer.new(connection_details)
      ]
      percona_logger = Departure::LoggerFactory.build(sanitizers: sanitizers, verbose: verbose)
      cli_generator = Departure::CliGenerator.new(connection_details)

      runner = Departure::Runner.new(
        percona_logger,
        cli_generator,
        mysql2_connection
      )

      connection_options = { mysql_adapter: mysql2_connection }

      ConnectionAdapters::DepartureAdapter.new(
        runner,
        logger,
        connection_options,
        config
      )
    end
  end
end
