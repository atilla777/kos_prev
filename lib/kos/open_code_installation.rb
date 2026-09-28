require "json"
require "pathname"

module Kos
  module OpenCodeInstallation
    SCHEMA = 1
    INVENTORY = {
      "commands" => %w[kos.md].freeze,
      "agents" => %w[kos-worker.md].freeze,
      "skills" => %w[kos kos-cli kos-worker okf].freeze
    }.freeze
    SOURCE_ID_PATTERN = /\Asha256:[0-9a-f]{64}\z/
    MANAGED_NAME_PATTERNS = {
      "commands" => /\Akos(?:-[A-Za-z0-9._-]+)?\.md\z/,
      "agents" => /\Akos(?:-[A-Za-z0-9._-]+)?\.md\z/,
      "skills" => /\A(?:kos(?:-[A-Za-z0-9._-]+)?|okf)\z/
    }.freeze

    class Invalid < StandardError; end

    module_function

    def manifest_path(environment: ENV, explicit: nil)
      configured = explicit || environment["KOS_OPENCODE_MANIFEST"]
      return absolute_path(configured, "OpenCode installation manifest") if configured

      xdg_config_home = environment["XDG_CONFIG_HOME"]
      config_root = if xdg_config_home && !xdg_config_home.empty? && Pathname(xdg_config_home).absolute?
        Pathname(xdg_config_home).expand_path
      else
        Pathname(environment.fetch("HOME", "~")).expand_path.join(".config")
      end
      config_root.join("opencode/kos-installation.json")
    end

    def read_manifest(path, require_current_inventory: false)
      path = Pathname(path)
      raise Invalid, "installation manifest must not be a symbolic link: #{path}" if path.symlink?
      value = JSON.parse(path.binread)
      raise Invalid, "installation manifest must contain a JSON object" unless value.is_a?(Hash)
      raise Invalid, "unsupported installation manifest schema #{value["schema"].inspect}" unless value["schema"] == SCHEMA
      raise Invalid, "installation manifest version must be a nonempty string" unless
        value["version"].is_a?(String) && !value["version"].empty?
      raise Invalid, "installation manifest source_id is invalid" unless value["source_id"].is_a?(String) &&
        value["source_id"].match?(SOURCE_ID_PATTERN)

      INVENTORY.each_key do |kind|
        names = value[kind]
        unless names.is_a?(Array) && names.all? { |name| name.is_a?(String) && name.match?(MANAGED_NAME_PATTERNS.fetch(kind)) } &&
            names.uniq.length == names.length
          raise Invalid, "installation manifest #{kind} must contain unique KOS-managed names"
        end
      end

      if require_current_inventory && INVENTORY.any? { |kind, names| value[kind].sort != names.sort }
        raise Invalid, "installation manifest inventory does not match this KOS release"
      end

      value
    rescue Errno::ENOENT
      raise Invalid, "installation manifest is missing: #{path}"
    rescue SystemCallError => error
      raise Invalid, "cannot read installation manifest #{path}: #{error.message}"
    rescue JSON::ParserError => error
      raise Invalid, "installation manifest is invalid JSON: #{error.message}"
    end

    def absolute_path(value, label)
      path = Pathname(value)
      raise Invalid, "#{label} path must be absolute" unless path.absolute?

      path.expand_path
    end
    private_class_method :absolute_path
  end
end
