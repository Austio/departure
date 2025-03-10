require 'active_record/connection_adapters/abstract_mysql_adapter'
require 'active_record/connection_adapters/statement_pool'
require 'active_record/connection_adapters/mysql2_adapter'
require 'active_support/core_ext/string/filters'
require_relative './patch_connection_handling'
require 'departure'
require 'forwardable'

module ActiveRecord
  module ConnectionAdapters
    class Rails72DepartureAdapter < AbstractMysqlAdapter
      TYPE_MAP = Type::TypeMap.new.tap { |m| initialize_type_map(m) } if defined?(initialize_type_map)

      class Column < ActiveRecord::ConnectionAdapters::MySQL::Column
        def adapter
          Rails72DepartureAdapter
        end
      end

      class SchemaCreation < ActiveRecord::ConnectionAdapters::MySQL::SchemaCreation
        def visit_DropForeignKey(name) # rubocop:disable Style/MethodName
          fk_name =
            if name =~ /^__(.+)/
              Regexp.last_match(1)
            else
              "_#{name}"
            end

          "DROP FOREIGN KEY #{fk_name}"
        end
      end

      extend Forwardable

      include ForAlterStatements unless method_defined?(:change_column_for_alter)

      ADAPTER_NAME = 'Percona'.freeze

      def self.new_client(config)
        connection_details = Departure::ConnectionDetails.new(config)
        verbose = ActiveRecord::Migration.verbose
        sanitizers = [
          Departure::LogSanitizers::PasswordSanitizer.new(connection_details)
        ]
        percona_logger = Departure::LoggerFactory.build(sanitizers: sanitizers, verbose: verbose)
        cli_generator = Departure::CliGenerator.new(connection_details)

        mysql_adapter = ActiveRecord::ConnectionAdapters::Mysql2Adapter.new(config.merge(adapter: 'mysql2'))

        Departure::Runner.new(
          percona_logger,
          cli_generator,
          mysql_adapter
        )
      end

      def initialize(config)
        super

        @config[:flags] ||= 0

        if @config[:flags].is_a? Array
          @config[:flags].push 'FOUND_ROWS'
        else
          @config[:flags] |= ::Mysql2::Client::FOUND_ROWS
        end

        @prepared_statements = false
      end

      def write_query?(sql) # :nodoc:
        !ActiveRecord::ConnectionAdapters::AbstractAdapter.build_read_query_regexp(
          :desc, :describe, :set, :show, :use
        ).match?(sql)
      end

      def exec_delete(sql, name, binds)
        execute(to_sql(sql, binds), name)
        mysql_adapter.raw_connection.affected_rows
      end
      alias exec_update exec_delete

      def exec_insert(sql, name, binds, pky = nil, sequence_name = nil, returning: nil) # rubocop:disable Lint/UnusedMethodArgument, Metrics/Metrics/ParameterLists
        execute(to_sql(sql, binds), name)
      end

      def internal_exec_query(sql, name = 'SQL', _binds = [], **_kwargs) # :nodoc:
        result = execute(sql, name)
        fields = result.fields if defined?(result.fields)
        ActiveRecord::Result.new(fields, result.to_a)
      end
      alias exec_query internal_exec_query

      # Executes a SELECT query and returns an array of rows. Each row is an
      # array of field values.

      def select_rows(arel, name = nil, binds = [])
        select_all(arel, name, binds).rows
      end

      # Executes a SELECT query and returns an array of record hashes with the
      # column names as keys and column values as values.
      def select(sql, name = nil, binds = [], **kwargs)
        exec_query(sql, name, binds, **kwargs)
      end

      # Returns true, as this adapter supports migrations
      def supports_migrations?
        true
      end

      # rubocop:disable Metrics/ParameterLists
      def new_column(field, default, type_metadata, null, table_name, default_function, collation, comment)
        Column.new(field, default, type_metadata, null, table_name, default_function, collation, comment)
      end
      # rubocop:enable Metrics/ParameterLists

      # Adds a new index to the table
      #
      # @param table_name [String, Symbol]
      # @param column_name [String, Symbol]
      # @param options [Hash] optional
      def add_index(table_name, column_name, options = {})
        index_definition, = add_index_options(table_name, column_name, **options)
        execute <<-SQL.squish
          ALTER TABLE #{quote_table_name(index_definition.table)}
            ADD #{schema_creation.accept(index_definition)}
        SQL
      end

      # Remove the given index from the table.
      #
      # @param table_name [String, Symbol]
      # @param options [Hash] optional
      def remove_index(table_name, column_name = nil, **options)
        return if options[:if_exists] && !index_exists?(table_name, column_name, **options)

        index_name = index_name_for_remove(table_name, column_name, options)

        execute "ALTER TABLE #{quote_table_name(table_name)} DROP INDEX #{quote_column_name(index_name)}"
      end

      def schema_creation
        SchemaCreation.new(self)
      end

      def change_table(table_name, _options = {})
        recorder = ActiveRecord::Migration::CommandRecorder.new(self)
        yield update_table_definition(table_name, recorder)
        bulk_change_table(table_name, recorder.commands)
      end

      def full_version
        @full_version ||= get_full_version
      end

      def get_full_version # rubocop:disable Style/AccessorMethodName
        @get_full_version ||= @raw_connection.database_adapter.get_database_version.full_version_string
      end

      def last_inserted_id(result)
        @raw_connection.database_adapter.send(:last_inserted_id, result)
      end


      # Mostly a copy from ActiveRecord::ConnectionAdapters::MySQL::SchemaStatements
      # original method was not returning index names due to a return in each_hash
      def indexes(table_name)
        indexes = []
        current_index = nil
        execute_and_free("SHOW KEYS FROM #{quote_table_name(table_name)}", "SCHEMA") do |result|
          # This is the root line change, the underlying definition ought yield to the block but it was not returning
          # connection definition is this
          #From: activerecord-7.2.2.1/lib/active_record/connection_adapters/mysql2_adapter.rb:96 ActiveRecord::ConnectionAdapters::Mysql2Adapter#each_hash:
          #
          #      95: def each_hash(result, &block) # :nodoc:
          #  =>  96:   if block_given?
          #      97:     result.each(as: :hash, symbolize_keys: true, &block)
          #      98:   else
          #      99:     to_enum(:each_hash, result)
          #     100:   end
          #     101: end

          each_hash(result).each do |row|
            if current_index != row[:Key_name]
              next if row[:Key_name] == "PRIMARY" # skip the primary key
              current_index = row[:Key_name]

              mysql_index_type = row[:Index_type].downcase.to_sym
              case mysql_index_type
              when :fulltext, :spatial
                index_type = mysql_index_type
              when :btree, :hash
                index_using = mysql_index_type
              end

              indexes << [
                row[:Table],
                row[:Key_name],
                row[:Non_unique].to_i == 0,
                [],
                lengths: {},
                orders: {},
                type: index_type,
                using: index_using,
                comment: row[:Index_comment].presence
              ]
            end

            if row[:Expression]
              expression = row[:Expression].gsub("\\'", "'")
              expression = +"(#{expression})" unless expression.start_with?("(")
              indexes.last[-2] << expression
              indexes.last[-1][:expressions] ||= {}
              indexes.last[-1][:expressions][expression] = expression
              indexes.last[-1][:orders][expression] = :desc if row[:Collation] == "D"
            else
              indexes.last[-2] << row[:Column_name]
              indexes.last[-1][:lengths][row[:Column_name]] = row[:Sub_part].to_i if row[:Sub_part]
              indexes.last[-1][:orders][row[:Column_name]] = :desc if row[:Collation] == "D"
            end
          end
        end

        indexes.map do |index|
          options = index.pop

          if expressions = options.delete(:expressions)
            orders = options.delete(:orders)
            lengths = options.delete(:lengths)

            columns = index[-1].to_h { |name|
              [ name.to_sym, expressions[name] || +quote_column_name(name) ]
            }

            index[-1] = add_options_for_index_columns(
              columns, order: orders, length: lengths
            ).values.join(", ")
          end

          IndexDefinition.new(*index, **options)
        end
      rescue StatementInvalid => e
        if e.message.match?(/Table '.+' doesn't exist/)
          []
        else
          raise
        end
      end

      private

      attr_reader :mysql_adapter

      def each_hash(result) # :nodoc:
        @raw_connection.database_adapter.each_hash(result)
      end

      # Must return the MySQL error number from the exception, if the exception has an
      # error number.
      def error_number(_exception) # :nodoc:
        @raw_connection.database_adapter.error_number(_exception)
      end

      def raw_execute(sql, name, async: false, allow_retry: false, materialize_transactions: true)
        log(sql, name, async: async) do |notification_payload|
          with_raw_connection(allow_retry: allow_retry, materialize_transactions: materialize_transactions) do |conn|
            sync_timezone_changes(conn)
            result = conn.query(sql)
            # conn.abandon_results!
            verified! if allow_retry
            handle_warnings(sql)
            if result.is_a? Process::Status
              notification_payload[:exit_code] = result.exitstatus
              notification_payload[:exit_pid] = result.pid
            else
              notification_payload[:row_count] = result&.size || 0
            end
            result
          end
        end
      end

      def connect
        @raw_connection = self.class.new_client(@config)
      rescue ConnectionNotEstablished => e
        raise e.set_pool(@pool)
      end

      def reconnect
        @lock.synchronize do
          @raw_connection&.close
          @raw_connection = nil
          connect
        end
      end
    end
  end
end
