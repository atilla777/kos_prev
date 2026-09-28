require "test_helper"

class BuiltInCatalogTest < ActiveSupport::TestCase
  test "installs concise generic immutable revisions idempotently" do
    assert_difference -> { Workflow.count }, 3 do
      BuiltInCatalog.install!
    end
    assert_no_difference -> { Workflow.count } do
      BuiltInCatalog.install!
    end

    assert BuiltInCatalog.installed?
    assert_equal %w[brief development fix], Workflow.where(revision: 1).order(:key).pluck(:key)
    Workflow.where(revision: 1).find_each do |workflow|
      workflow.definition_json.fetch("steps").each do |step|
        assert_equal %w[id instruction name outcomes], step.keys.sort
        assert_equal({ "pause" => "needs_human" }, step.dig("outcomes", "needs_human"))
        assert_equal({ "pause" => "blocked" }, step.dig("outcomes", "blocked"))
      end
      assert workflow.valid?
    end
  end
end
