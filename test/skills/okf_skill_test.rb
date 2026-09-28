require "test_helper"
require "yaml"

class OkfSkillTest < ActiveSupport::TestCase
  SKILL_PATH = Rails.root.join("skills/okf/SKILL.md")
  BUNDLE_PATH = Rails.root.join("specs")

  test "is a concise discoverable confined preservation skill" do
    source = File.read(SKILL_PATH)
    normalized = source.gsub(/\s+/, " ")
    metadata = YAML.safe_load(source.match(/\A---\n(.*?)\n---/m)[1])

    assert_equal "okf", metadata.fetch("name")
    assert_match(/product behavior specifications/i, metadata.fetch("description"))
    assert_equal [ "SKILL.md" ], Dir.children(SKILL_PATH.dirname).sort
    assert_match(/refuse a symlinked bundle root/i, normalized)
    assert_includes normalized, "`specs/index.md`"
    assert_includes normalized, "nonempty string `type`"
    assert_match(/preserve unknown metadata.*unrelated body content/i, normalized)
    assert_match(/do not invent optional metadata/i, normalized)
  end

  test "ships a conformant linked product bundle" do
    root_index = File.read(BUNDLE_PATH.join("index.md"))
    metadata = YAML.safe_load(root_index.match(/\A---\n(.*?)\n---\n/m)[1])
    assert_equal({ "okf_version" => "0.2" }, metadata)

    concepts = Dir.glob(BUNDLE_PATH.join("**/*.md")).reject do |path|
      %w[index.md log.md].include?(File.basename(path))
    end
    assert_equal [ BUNDLE_PATH.join("kos.md").to_s ], concepts
    concepts.each do |path|
      frontmatter = YAML.safe_load(File.read(path).match(/\A---\n(.*?)\n---\n/m)[1])
      assert frontmatter.fetch("type").is_a?(String)
      assert frontmatter.fetch("type").strip.present?
    end

    Dir.glob(BUNDLE_PATH.join("**/*.md")).each do |path|
      File.read(path).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
        next if target.match?(/\A[a-z][a-z0-9+.-]*:/i)

        resolved = target.start_with?("/") ? BUNDLE_PATH.join(target.delete_prefix("/")) : Pathname(path).dirname.join(target)
        assert resolved.exist?, "#{path} links to missing #{target}"
      end
    end
  end
end
