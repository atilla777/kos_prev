require "pathname"
require_relative "../lib/kos/api_token"

module Kos
  class ConfigurationError < StandardError; end

  module Configuration
    module_function

    def data_home(environment = ENV, home: Dir.home)
      explicit_home = environment["KOS_DATA_HOME"]
      unless blank?(explicit_home)
        raise ConfigurationError, "KOS_DATA_HOME must be an absolute path" unless absolute?(explicit_home)

        return File.expand_path(explicit_home)
      end

      xdg_data_home = environment["XDG_DATA_HOME"]
      if !blank?(xdg_data_home) && absolute?(xdg_data_home)
        return File.join(File.expand_path(xdg_data_home), "kos")
      end

      File.join(home, ".local", "share", "kos")
    end

    def validate_api_token!(token)
      normalized = Kos::ApiToken.normalize(token)
      return normalized if normalized

      raise ConfigurationError, "KOS_API_TOKEN must be a non-empty HTTP header value"
    end

    def lease_duration(environment = ENV)
      seconds = Integer(environment.fetch("KOS_LEASE_SECONDS", "21600"), 10)
      return seconds if seconds.positive?

      raise ConfigurationError, "KOS_LEASE_SECONDS must be a positive integer"
    rescue ArgumentError
      raise ConfigurationError, "KOS_LEASE_SECONDS must be a positive integer"
    end

    def validate_data_home!(data_home, repository_root:)
      expanded_home = File.expand_path(data_home)
      expanded_root = File.expand_path(repository_root)
      return data_home unless expanded_home == expanded_root || expanded_home.start_with?("#{expanded_root}/")

      raise ConfigurationError, "KOS data home must be outside the application repository"
    end

    def blank?(value)
      value.nil? || value.strip.empty?
    end

    def absolute?(path)
      Pathname.new(path).absolute?
    end
    private_class_method :absolute?, :blank?
  end
end
