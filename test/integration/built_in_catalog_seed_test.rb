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
      assert_equal({
        "keys" => %w[brief development fix],
        "revisions" => [ BuiltInCatalog::REVISION, BuiltInCatalog::REVISION, BuiltInCatalog::REVISION ]
      }, first)
    end
  end

  test "seeding a changed catalog creates new immutable revisions idempotently" do
    Dir.mktmpdir("kos-seed-upgrade") do |data_home|
      environment = {
        "RAILS_ENV" => "development", "KOS_API_TOKEN" => "seed-test-token", "KOS_DATA_HOME" => data_home,
        "DATABASE_URL" => nil
      }
      run_rails(environment, "db:prepare")
      run_rails(environment, "runner", legacy_catalog_script)

      legacy = catalog(environment)
      run_rails(environment, "db:seed")
      upgraded = catalog(environment)
      run_rails(environment, "db:seed")

      legacy_revision = BuiltInCatalog::REVISION - 1
      assert_equal({
        "keys" => %w[brief development fix], "revisions" => [ legacy_revision, legacy_revision, legacy_revision ]
      }, legacy)
      assert_equal({
        "keys" => %w[brief brief development development fix fix],
        "revisions" => [ legacy_revision, BuiltInCatalog::REVISION, legacy_revision, BuiltInCatalog::REVISION,
          legacy_revision, BuiltInCatalog::REVISION ]
      }, upgraded)
      assert_equal upgraded, catalog(environment)
    end
  end

  private

  def catalog(environment)
    script = <<~RUBY
      workflows = Workflow.order(:key, :revision)
      puts({ keys: workflows.pluck(:key), revisions: workflows.pluck(:revision) }.to_json)
    RUBY
    JSON.parse(run_rails(environment, "runner", script).lines.last)
  end

  def legacy_catalog_script
    <<~RUBY
      Workflow.delete_all
      BuiltInCatalog.definitions.each do |key, definition|
        legacy = definition.deep_dup
        legacy.fetch("steps").first["instruction"] += " Legacy."
        Workflow.create!(key: key, name: key.titleize, revision: #{BuiltInCatalog::REVISION - 1},
          definition_json: legacy)
      end
    RUBY
  end

  def run_rails(environment, *arguments)
    output, error, status = Open3.capture3(environment, Rails.root.join("bin/rails").to_s, *arguments)
    assert_predicate status, :success?, error
    output
  end
end
