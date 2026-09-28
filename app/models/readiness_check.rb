require "tempfile"

class ReadinessCheck
  class Error < StandardError
    attr_reader :component

    def initialize(component, cause = nil)
      @component = component
      super("KOS is not ready")
      set_backtrace(cause.backtrace) if cause
    end
  end

  def self.call(data_home: Rails.application.config.x.kos.data_home)
    new(data_home:).call
  end

  def initialize(data_home:)
    @data_home = Pathname(data_home)
  end

  def call
    check(:database) do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        raise "database query failed" unless connection.select_value("SELECT 1").to_i == 1

        connection.transaction(requires_new: true) do
          connection.execute("UPDATE workflows SET revision = revision WHERE id = (SELECT MIN(id) FROM workflows)")
          raise ActiveRecord::Rollback
        end
      end
    end
    check(:migrations) { ActiveRecord::Migration.check_all_pending! }
    check(:catalog) { raise "catalog mismatch" unless BuiltInCatalog.installed? }
    check(:data_home) do
      raise "data home is not a directory" unless @data_home.directory?

      Tempfile.create("kos-readiness", @data_home.to_s) do |file|
        file.write("ready\n")
        file.flush
        file.fsync
      end
    end
    true
  end

  private

  def check(component)
    yield
  rescue StandardError => error
    raise Error.new(component, error)
  end
end
