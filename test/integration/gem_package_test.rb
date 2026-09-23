require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class GemPackageTest < ActiveSupport::TestCase
  test "builds and installs a standalone kos executable" do
    Dir.mktmpdir("kos-gem") do |directory|
      root = Pathname(directory)
      package = root.join("kos.gem")
      gem_home = root.join("gem-home")
      bin_dir = root.join("bin")

      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "build", "kos.gemspec",
        "--output", package.to_s, chdir: Rails.root.to_s)
      assert_predicate status, :success?, error

      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "install", package.to_s,
        "--install-dir", gem_home.to_s, "--bindir", bin_dir.to_s, "--no-document")
      assert_predicate status, :success?, error

      environment = {
        "BUNDLE_GEMFILE" => nil, "GEM_HOME" => gem_home.to_s, "GEM_PATH" => gem_home.to_s,
        "RUBYGEMS_GEMDEPS" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil
      }
      output, error, status = Open3.capture3(environment, bin_dir.join("kos").to_s, "--version", chdir: directory)

      assert_predicate status, :success?, error
      assert_equal "kos #{Kos::VERSION}\n", output
      assert_empty error

      output, error, status = Open3.capture3(environment, bin_dir.join("kos").to_s, "--help", chdir: directory)
      assert_predicate status, :success?, error
      assert_includes output, "KOS task coordination CLI"
    end
  end

  test "installs the complete OpenCode integration from the checkout" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      config_home = root.join("config/opencode")
      stale_agent = config_home.join("agents/kos-step.md")
      stale_orchestrator = config_home.join("agents/kos-orchestrator.md")
      stale_skill = config_home.join("skills/kos/obsolete.md")
      FileUtils.mkdir_p(stale_agent.dirname)
      FileUtils.mkdir_p(stale_skill.dirname)
      stale_agent.write("stale\n")
      stale_orchestrator.write("stale\n")
      stale_skill.write("stale\n")

      2.times do
        output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
          "--config-home", config_home.to_s)

        assert_predicate status, :success?, error
        assert_includes output, config_home.to_s
      end
      assert_equal %w[kos-brief.md kos-fix.md kos.md], installed_names(config_home.join("commands"))
      assert_equal %w[
        kos-brief.md kos-diagnose.md kos-document.md kos-implement.md kos-plan.md kos-publish.md kos-review.md
        kos-step-advanced.md kos-step-standard.md kos-verify.md
      ], installed_names(config_home.join("agents"))
      assert_equal %w[kos kos-brief kos-cli kos-create kos-git kos-step okf],
        installed_names(config_home.join("skills"))
      refute_predicate stale_agent, :exist?
      refute_predicate stale_orchestrator, :exist?
      refute_predicate stale_skill, :exist?

      assert_matching_tree Rails.root.join(".opencode/commands"), config_home.join("commands")
      assert_matching_tree Rails.root.join(".opencode/agents"), config_home.join("agents")
      assert_matching_tree Rails.root.join("skills"), config_home.join("skills")
    end
  end

  test "refuses symbolic-link OpenCode destinations" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      config_home = root.join("config/opencode")
      outside = root.join("outside")
      FileUtils.mkdir_p(config_home)
      FileUtils.mkdir_p(outside)
      outside.join("marker").write("preserved\n")
      FileUtils.ln_s(outside, config_home.join("commands"))

      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      refute_predicate status, :success?
      assert_includes error, "Refusing symbolic-link destination"
      assert_equal "preserved\n", outside.join("marker").read
      refute_predicate config_home.join("agents"), :exist?
    end
  end

  test "fails instead of nesting a skill when replacement cannot be removed" do
    Dir.mktmpdir("kos-opencode") do |directory|
      config_home = Pathname(directory).join("config/opencode")
      skills_directory = config_home.join("skills")
      installed_skill = skills_directory.join("kos")
      FileUtils.mkdir_p(installed_skill)
      FileUtils.chmod(0o555, skills_directory)

      _output, _error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      refute_predicate status, :success?
      refute_predicate installed_skill.join("kos"), :exist?
    ensure
      FileUtils.chmod(0o755, skills_directory) if skills_directory&.exist?
    end
  end

  private

  def installed_names(directory)
    directory.children.map { |path| path.basename.to_s }.sort
  end

  def assert_matching_tree(source, destination)
    source_files = source.glob("**/*").select(&:file?).map { |path| path.relative_path_from(source).to_s }.sort
    destination_files = destination.glob("**/*").select(&:file?).map do |path|
      path.relative_path_from(destination).to_s
    end.sort

    assert_equal source_files, destination_files
    source_files.each do |relative_path|
      assert_equal source.join(relative_path).binread, destination.join(relative_path).binread
    end
  end
end
