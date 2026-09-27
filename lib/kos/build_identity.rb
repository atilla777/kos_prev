require "digest"
require "open3"
require "pathname"
require "set"

module Kos
  module BuildIdentity
    PATTERNS = %w[
      .opencode/**/*.md
      Gemfile.lock
      app/**/*.rb
      bin/*
      config/**/*.rb
      config/**/*.yml
      db/**/*.rb
      kos.gemspec
      lib/**/*.rb
      skills/**/*.md
    ].freeze

    module_function

    def source_id(root: default_root)
      root = Pathname(root).expand_path
      paths = PATTERNS.flat_map { |pattern| root.glob(pattern) }.select(&:file?).uniq
      if (tracked = tracked_paths(root))
        paths.select! { |path| tracked.include?(path.relative_path_from(root).to_s) }
      end
      paths.sort!
      raise "KOS operational source inventory is empty" if paths.empty?

      digest = Digest::SHA256.new
      paths.each do |path|
        relative = path.relative_path_from(root).to_s.b
        contents = path.binread
        digest << [ relative.bytesize ].pack("Q>") << relative
        digest << [ contents.bytesize ].pack("Q>") << contents
      end
      "sha256:#{digest.hexdigest}"
    end

    def installed_source_id
      specification = Gem.loaded_specs["kos"] if defined?(Gem)
      specification&.metadata&.fetch("kos_source_id", nil) || source_id
    end

    def default_root
      Pathname(__dir__).join("../..").expand_path
    end

    def tracked_paths(root)
      top_level, _error, status = Open3.capture3("git", "-C", root.to_s, "rev-parse", "--show-toplevel")
      return unless status.success? && Pathname(top_level.strip).expand_path == root

      output, _error, status = Open3.capture3("git", "-C", root.to_s, "ls-files", "-z")
      output.split("\0").to_set if status.success?
    rescue Errno::ENOENT
      nil
    end
    private_class_method :default_root, :tracked_paths
  end
end
