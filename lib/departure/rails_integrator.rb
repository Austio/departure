# frozen_string_literal: true

module Departure
  class RailsIntegrator
    extend Forwardable

    class << self
      def for_current
        self.for(ActiveRecord::VERSION)
      end

      def for(ar_version)
        if ar_version::MAJOR >= 7 && ar_version::MINOR >= 2
          V7_2
        else
          BaseIntegration
        end
      end
    end

    class BaseIntegration
      class << self
        def register_integrations
          ActiveSupport.on_load(:active_record) do
            ActiveRecord::Migration.class_eval do
              include Departure::Migration
            end
          end
        end
      end
    end

    class V7_2 < BaseIntegration
      class << self
        def register_integrations
          ActiveSupport.on_load(:active_record) do
            ActiveRecord::Migration.class_eval do
              include Departure::Migration
            end
          end

          ActiveRecord::ConnectionAdapters.register "percona",
                                                    "ActiveRecord::ConnectionAdapters::DepartureAdapter",
                                                    "active_record/connection_adapters/percona_adapter"
        end
      end
    end
  end
end
