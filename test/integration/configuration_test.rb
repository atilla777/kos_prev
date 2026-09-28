require "test_helper"
require "open3"
require "tmpdir"

class ConfigurationTest < ActiveSupport::TestCase
  test "uses the explicit KOS data home" do
    environment = { "KOS_DATA_HOME" => "/var/lib/kos", "XDG_DATA_HOME" => "/ignored" }

    assert_equal "/var/lib/kos", Kos::Configuration.data_home(environment, home: "/home/test")
  end

  test "uses the XDG data home when no explicit home is configured" do
    environment = { "XDG_DATA_HOME" => "/home/test/data" }

    assert_equal "/home/test/data/kos", Kos::Configuration.data_home(environment, home: "/ignored")
  end

  test "falls back to the local user data directory" do
    assert_equal "/home/test/.local/share/kos", Kos::Configuration.data_home({}, home: "/home/test")
  end

  test "rejects a relative explicit data home" do
    error = assert_raises(Kos::ConfigurationError) do
      Kos::Configuration.data_home({ "KOS_DATA_HOME" => "storage" }, home: "/home/test")
    end

    assert_equal "KOS_DATA_HOME must be an absolute path", error.message
  end

  test "ignores a relative XDG data home" do
    environment = { "XDG_DATA_HOME" => "relative-data" }

    assert_equal "/home/test/.local/share/kos", Kos::Configuration.data_home(environment, home: "/home/test")
  end

  test "rejects a data home inside the application repository" do
    error = assert_raises(Kos::ConfigurationError) do
      Kos::Configuration.validate_data_home!("/srv/kos/app/data", repository_root: "/srv/kos/app")
    end

    assert_equal "KOS data home must be outside the application repository", error.message
    assert_equal "/srv/kos/data",
      Kos::Configuration.validate_data_home!("/srv/kos/data", repository_root: "/srv/kos/app")
  end

  test "rejects missing and blank API tokens" do
    error = assert_raises(Kos::ConfigurationError) do
      Kos::Configuration.validate_api_token!(nil)
    end

    assert_equal "KOS_API_TOKEN must be a non-empty HTTP header value", error.message
    assert_raises(Kos::ConfigurationError) { Kos::Configuration.validate_api_token!("  ") }
  end

  test "accepts only token values that can be used unchanged in an HTTP header" do
    token = "token value._~+/="

    assert_equal token, Kos::Configuration.validate_api_token!(token)
    [ " leading", "trailing ", "tab\tvalue", "line\rbreak", "line\nbreak", "delete\x7f", "\xff".b ].each do |value|
      assert_raises(Kos::ConfigurationError) { Kos::Configuration.validate_api_token!(value) }
    end
  end

  test "separate server and OpenCode environments derive the same nondefault worktree path" do
    data_home = "/srv/kos-instance"
    server_environment = { "KOS_DATA_HOME" => data_home, "KOS_API_TOKEN" => "server-token" }
    opencode_environment = { "KOS_DATA_HOME" => data_home, "KOS_API_URL" => "http://127.0.0.1:3000" }

    server_home = Kos::Configuration.data_home(server_environment, home: "/server-default")
    output, error, status = Open3.capture3(opencode_environment, RbConfig.ruby,
      Rails.root.join("test/support/worktree_path_process.rb").to_s, "7", "19")

    assert_predicate status, :success?, error
    assert_equal "#{File.join(server_home, "worktrees", "7", "19")}\n", output

    [ {}, { "KOS_DATA_HOME" => "relative" } ].each do |invalid_environment|
      _output, error, status = Open3.capture3(invalid_environment, RbConfig.ruby,
        Rails.root.join("test/support/worktree_path_process.rb").to_s, "7", "19")
      refute_predicate status, :success?
      assert_match(/KOS_DATA_HOME/, error)
    end
  end

  test "boots development with a token and creates its external data directory" do
    Dir.mktmpdir("kos-data") do |temporary_directory|
      data_home = File.join(temporary_directory, "data")
      environment = {
        "RAILS_ENV" => "development",
        "KOS_API_TOKEN" => "development-token",
        "KOS_DATA_HOME" => data_home
      }

      output, error, status = Open3.capture3(
        environment,
        Rails.root.join("bin/rails").to_s,
        "runner",
        "print Rails.application.config.database_configuration.fetch('development').fetch('database')"
      )

      assert_predicate status, :success?, error
      assert_equal File.join(data_home, "development.sqlite3"), output
      assert_path_exists data_home
    end
  end

  test "refuses to boot development without a token" do
    Dir.mktmpdir("kos-data") do |data_home|
      environment = {
        "RAILS_ENV" => "development",
        "KOS_API_TOKEN" => nil,
        "KOS_DATA_HOME" => data_home
      }

      _output, error, status = Open3.capture3(
        environment,
        Rails.root.join("bin/rails").to_s,
        "runner",
        "print 'booted'"
      )

      refute_predicate status, :success?
      assert_includes error, "KOS_API_TOKEN must be a non-empty HTTP header value"
    end
  end

  test "refuses to boot production without a token" do
    Dir.mktmpdir("kos-data") do |data_home|
      environment = {
        "RAILS_ENV" => "production",
        "KOS_API_TOKEN" => nil,
        "KOS_DATA_HOME" => data_home
      }

      _output, error, status = Open3.capture3(
        environment,
        Rails.root.join("bin/rails").to_s,
        "runner",
        "print 'booted'"
      )

      refute_predicate status, :success?
      assert_includes error, "KOS_API_TOKEN must be a non-empty HTTP header value"
    end
  end

  test "refuses to boot with a token that cannot be used as an HTTP header" do
    Dir.mktmpdir("kos-data") do |data_home|
      [ "line\nbreak", "tab\tvalue" ].each do |token|
        environment = { "RAILS_ENV" => "development", "KOS_API_TOKEN" => token, "KOS_DATA_HOME" => data_home }
        _output, error, status = Open3.capture3(
          environment, Rails.root.join("bin/rails").to_s, "runner", "print 'booted'"
        )

        refute_predicate status, :success?
        assert_includes error, "KOS_API_TOKEN must be a non-empty HTTP header value"
      end
    end
  end

  test "boots production with eager-loaded application and library constants" do
    Dir.mktmpdir("kos-data") do |temporary_directory|
      data_home = File.join(temporary_directory, "data")
      environment = {
        "RAILS_ENV" => "production",
        "KOS_API_TOKEN" => "production-token",
        "KOS_DATA_HOME" => data_home,
        "SECRET_KEY_BASE" => "production-secret-key-base"
      }

      output, error, status = Open3.capture3(
        environment,
        Rails.root.join("bin/rails").to_s,
        "runner",
        "print [Rails.application.config.eager_load, Kos::CLI.name, " \
          "Rails.application.config.database_configuration.fetch('production').fetch('database')].join('|')"
      )

      assert_predicate status, :success?, error
      assert_equal "true|Kos::CLI|#{File.join(data_home, "production.sqlite3")}", output
      assert_path_exists data_home
    end
  end

  test "keeps the test database inside the isolated temporary directory" do
    database = Rails.application.config.database_configuration.fetch("test").fetch("database")

    assert_equal "tmp/test.sqlite3", database
  end
end
