require "test_helper"
require "tmpdir"

class BuildIdentityTest < ActiveSupport::TestCase
  test "uses stable path-aware content identity without git metadata" do
    Dir.mktmpdir("kos-build-identity") do |directory|
      root = Pathname(directory)
      root.join("app").mkpath
      root.join("app/example.rb").write("one\n")

      first = Kos::BuildIdentity.source_id(root:)
      assert_match(/\Asha256:[0-9a-f]{64}\z/, first)
      assert_equal first, Kos::BuildIdentity.source_id(root:)

      root.join("app/example.rb").rename(root.join("app/renamed.rb"))
      renamed = Kos::BuildIdentity.source_id(root:)
      refute_equal first, renamed

      root.join("app/renamed.rb").write("two\n")
      refute_equal renamed, Kos::BuildIdentity.source_id(root:)
    end
  end

  test "ignores untracked files in a git checkout" do
    Dir.mktmpdir("kos-build-identity") do |directory|
      root = Pathname(directory)
      root.join("app").mkpath
      root.join("app/example.rb").write("tracked\n")
      _output, error, status = Open3.capture3("git", "init", "--quiet", root.to_s)
      assert_predicate status, :success?, error
      _output, error, status = Open3.capture3("git", "-C", root.to_s, "add", "app/example.rb")
      assert_predicate status, :success?, error

      tracked = Kos::BuildIdentity.source_id(root:)
      root.join("app/untracked.rb").write("local\n")
      assert_equal tracked, Kos::BuildIdentity.source_id(root:)

      root.join("app/example.rb").write("changed\n")
      refute_equal tracked, Kos::BuildIdentity.source_id(root:)
    end
  end
end
