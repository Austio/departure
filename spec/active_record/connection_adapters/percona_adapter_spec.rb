require 'spec_helper'
require 'active_record/connection_adapters/percona_adapter'

describe ActiveRecord::ConnectionAdapters::DepartureAdapter do
  describe ActiveRecord::ConnectionAdapters::DepartureAdapter::Column do
    let(:field) { double(:field) }
    let(:default) { double(:default) }
    let(:cast_type) do
      if defined?(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::MysqlString)
        ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::MysqlString.new
      else
        ActiveRecord::Type.lookup(:string, adapter: :mysql2)
      end
    end
    let(:metadata) do
      ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(
        type: cast_type.type,
        sql_type: type,
        limit: cast_type.limit
      )
    end
    let(:mysql_metadata) do
      ActiveRecord::ConnectionAdapters::MySQL::TypeMetadata.new(metadata)
    end
    let(:type) { 'VARCHAR' }
    let(:null) { double(:null) }
    let(:collation) { double(:collation) }

    let(:column) do
      if ActiveRecord::VERSION::STRING >= "6.1"
        described_class.new("field", "default", mysql_metadata, null, collation: "collation")
      elsif ActiveRecord::VERSION::MAJOR == 6
        described_class.new(field, default, mysql_metadata, null, collation: collation)
      else
        described_class.new(field, default, mysql_metadata, type, null, collation)
      end
    end

    describe '#adapter' do
      subject { column.adapter }
      it do
        is_expected.to eq(
          ActiveRecord::ConnectionAdapters::DepartureAdapter
        )
      end
    end
  end

  let(:mysql_adapter) do
    instance_double(ActiveRecord::ConnectionAdapters::Mysql2Adapter)
  end

  let(:logger) { double(:logger, puts: true) }
  let(:connection_options) { { mysql_adapter: mysql_adapter } }

  let(:runner) { instance_double(Departure::Runner) }
  let(:cli_generator) do
    instance_double(
      Departure::CliGenerator,
      generate: 'percona command'
    )
  end

  let(:config) { { prepared_statements: '', runner: runner } }

  let(:adapter) do
    described_class.new(runner, logger, connection_options, config)
  end

  let(:mysql_client) { double(:mysql_client) }

  before do
    allow(mysql_client).to receive(:server_info).and_return(version: '5.7.19')
    allow(mysql_adapter).to receive(:raw_connection).and_return(mysql_client)
    allow(runner).to(
      receive(:execute).with('percona command').and_return(true)
    )
    allow(Departure::CliGenerator).to(
      receive(:new).and_return(cli_generator)
    )
    allow(Departure::Runner).to(
      receive(:new).with(logger)
    ).and_return(runner)
  end

  describe '#supports_migrations?' do
    subject { adapter.supports_migrations? }
    it { is_expected.to be true }
  end

  describe '#new_column' do
    let(:field) { double(:field) }
    let(:default) { double(:default) }
    let(:type) { double(:type) }
    let(:null) { double(:null) }
    let(:collation) { double(:collation) }
    let(:table_name) { double(:table_name) }
    let(:default_function) { double(:default_function) }
    let(:comment) { double(:comment) }

    it do
      expect(ActiveRecord::ConnectionAdapters::DepartureAdapter::Column).to receive(:new)
      adapter.new_column(field, default, type, null, table_name, default_function, collation, comment)
    end
  end

  describe 'schema statements' do
    describe '#add_index' do
      let(:table_name) { :foo }
      let(:column_name) { :bar_id }
      let(:index_name) { 'index_name' }
      let(:options) { {type: 'index_type'} }
      let(:index_type) { options[:type].upcase }
      let(:sql) { 'ADD index_type INDEX `index_name` (bar_id)' }
      let(:index_options) do
        if ActiveRecord::VERSION::STRING >= '6.1'
          [
            ActiveRecord::ConnectionAdapters::IndexDefinition.new(
              table_name,
              index_name,
              nil,
              [column_name],
              **options
            ),
            nil,
            false
          ]
        else
          [index_name, index_type, "#{column_name}"]
        end
      end

      let(:expected_sql) do
        if ActiveRecord::VERSION::STRING >= '6.1'
          "ALTER TABLE `#{table_name}` ADD #{index_type} INDEX `#{index_name}` (`#{column_name}`)"
        else
          "ALTER TABLE `#{table_name}` ADD #{index_type} INDEX `#{index_name}` (#{column_name})"
        end
      end

      before do
        allow(adapter).to(
          receive(:add_index_options)
          .with(table_name, column_name, options)
          .and_return(index_options)
        )
      end

      it 'passes the built SQL to #execute', activerecord_compatibility: "< 7.2" do
        expect(adapter).to receive(:execute).with(expected_sql)
        adapter.add_index(table_name, column_name, options)
      end
    end

    describe '#remove_index' do
      let(:table_name) { :foo }
      let(:options) { { column: :bar_id } }
      let(:sql) { 'DROP INDEX `index_name`' }

      before do
        allow(adapter).to(
          receive(:index_name_for_remove)
          .with(table_name, options)
          .and_return('index_name')
        )
        allow(adapter).to(
          receive(:index_name_for_remove)
          .with(table_name, nil, options)
          .and_return('index_name')
        )
      end

      it 'passes the built SQL to #execute' do
        expect(adapter).to(
          receive(:execute)
          .with("ALTER TABLE `#{table_name}` DROP INDEX `index_name`")
        )
        adapter.remove_index(table_name, **options)
      end
    end
  end

  describe '#exec_delete' do
    let(:sql) { 'DELETE FROM comments WHERE id = 1' }
    let(:affected_rows) { 1 }
    let(:name) { nil }
    let(:binds) { nil }

    before do
      allow(runner).to receive(:query).with(anything)
      allow(mysql_client).to receive(:affected_rows).and_return(affected_rows)
    end

    it 'executes the sql' do
      expect(adapter).to(receive(:execute).with(sql, name))
      adapter.exec_delete(sql, name, binds)
    end

    it 'returns the number of affected rows' do
      expect(adapter.exec_delete(sql, name, binds)).to eq(affected_rows)
    end
  end

  describe '#exec_insert' do
    let(:sql) { 'INSERT INTO comments (id) VALUES (20)' }
    let(:name) { nil }
    let(:binds) { nil }

    it 'executes the sql' do
      expect(adapter).to(receive(:execute).with(sql, name))
      adapter.exec_insert(sql, name, binds)
    end
  end

  describe '#exec_query' do
    let(:sql) { 'SELECT * FROM comments' }
    let(:name) { nil }
    let(:binds) { nil }

    before do
      allow(runner).to receive(:query).with(sql)
      allow(adapter).to(
        receive(:execute).with(sql, name).and_return(result_set)
      )
    end

    context 'when the adapter returns results', activerecord_compatibility: "< 7.2" do
      let(:result_set) { double(fields: [:id], to_a: [1]) }

      it 'executes the sql' do
        expect(adapter).to(
          receive(:execute).with(sql, name)
        ).and_return(result_set)

        adapter.exec_query(sql, name, binds)
      end

      it 'returns an ActiveRecord::Result' do
        expect(ActiveRecord::Result).to(
          receive(:new).with(result_set.fields, result_set.to_a)
        )
        adapter.exec_query(sql, name, binds)
      end
    end

    context 'when the adapter returns nil', activerecord_compatibility: "< 7.2" do
      let(:result_set) { nil }

      it 'executes the sql' do
        expect(adapter).to(
          receive(:execute).with(sql, name)
        ).and_return(result_set)

        adapter.exec_query(sql, name, binds)
      end

      it 'returns an ActiveRecord::Result' do
        expect(ActiveRecord::Result).to(
          receive(:new).with(nil, [])
        )
        adapter.exec_query(sql, name, binds)
      end
    end
  end

  describe '#last_inserted_id' do
    let(:result) { double(:result) }

    it 'delegates to the mysql adapter' do
      expect(mysql_adapter).to(
        receive(:last_inserted_id).with(result)
      )
      adapter.last_inserted_id(result)
    end
  end

  describe '#select_rows', activerecord_compatibility: "< 7.2" do
    subject { adapter.select_rows(sql, name) }

    let(:sql) { 'SELECT id, body FROM comments' }
    let(:name) { nil }

    let(:array_of_rows) { [%w[1 body], %w[2 body]] }
    let(:mysql2_result) do
      instance_double(Mysql2::Result, to_a: array_of_rows, fields: [:id, :body])
    end

    before do
      allow(adapter).to(
        receive(:execute).with(sql, name)
      ).and_return(mysql2_result)
    end

    it { is_expected.to match_array(array_of_rows) }
  end

  describe '#select' do
    subject { adapter.select(sql, name) }

    let(:sql) { 'SELECT id, body FROM comments' }
    let(:name) { nil }

    let(:array_of_rows) { [%w[1 body], %w[2 body]] }
    let(:mysql2_result) do
      instance_double(Mysql2::Result, fields: %w[id body], to_a: array_of_rows)
    end

    before do
      allow(adapter).to(
        receive(:execute).with(sql, name)
      ).and_return(mysql2_result)
    end

    it do
      is_expected.to match_array(
        [
          { 'id' => '1', 'body' => 'body' },
          { 'id' => '2', 'body' => 'body' }
        ]
      )
    end
  end
end
