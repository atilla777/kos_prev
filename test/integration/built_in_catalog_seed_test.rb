require "test_helper"
require "json"
require "open3"
require "tmpdir"

class BuiltInCatalogSeedTest < ActiveSupport::TestCase
  test "a fresh prepared database receives the idempotent built-in workflows" do
    Dir.mktmpdir("kos-seed") do |data_home|
      environment = {
        "RAILS_ENV" => "development", "KOS_API_TOKEN" => "seed-test-token", "KOS_DATA_HOME" => data_home,
        "DATABASE_URL" => nil
      }
      run_rails(environment, "db:prepare")
      first = catalog(environment)
      run_rails(environment, "db:seed")
      assert_equal first, catalog(environment)
      assert_equal({ "keys" => %w[brief development fix], "revisions" => [ 1, 1, 1 ] }, first)
    end
  end

  private

  def catalog(environment)
    script = "puts({ keys: Workflow.order(:key).pluck(:key), revisions: Workflow.order(:key).pluck(:revision) }.to_json)"
    JSON.parse(run_rails(environment, "runner", script).lines.last)
  end

  def run_rails(environment, *arguments)
    output, error, status = Open3.capture3(environment, Rails.root.join("bin/rails").to_s, *arguments)
    assert_predicate status, :success?, error
    output
  end
end
