require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class TaskCreationKeyMigrationTest < ActiveSupport::TestCase
  test "adds scoped request uniqueness and rolls back without changing existing task data" do
    Dir.mktmpdir("kos-creation-key-migration") do |directory|
      output, error, status = Open3.capture3(RbConfig.ruby,
        Rails.root.join("test/support/task_creation_key_migration_process.rb").to_s,
        File.join(directory, "migration.sqlite3"))
      assert_predicate status, :success?, error
      result = JSON.parse(output.lines.last)

      assert_equal 2, result.fetch("null_rows_before")
      assert result.fetch("duplicate_rejected")
      refute_includes result.fetch("columns_after_down"), "creation_key"
      refute_includes result.fetch("indexes_after_down"), "index_tasks_on_scoped_creation_key"
      assert_equal result.fetch("ids"), result.fetch("ids_after_down")
      assert_equal result.fetch("dependency"), result.fetch("dependency_after_down")
    end
  end
end
