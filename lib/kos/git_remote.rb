require "open3"

module Kos
  class GitRemote
    class Error < StandardError
      attr_reader :kind

      def initialize(kind, message)
        @kind = kind
        super(message)
      end
    end

    def initialize(environment: ENV, working_directory: Dir.pwd)
      @environment = environment
      @working_directory = working_directory
    end

    def url(remote)
      unless remote.is_a?(String) && !remote.empty? && remote.valid_encoding? &&
          remote == remote.strip && !remote.match?(/[\x00-\x1f\x7f]/)
        raise Error.new("invalid_remote", "Git remote name must be a non-empty valid name")
      end

      output, = git("rev-parse", "--is-inside-work-tree")
      raise Error.new("not_a_checkout", "current directory is not inside a Git working tree") unless output.strip == "true"

      remotes, = git("remote")
      unless remotes.lines(chomp: true).include?(remote)
        raise Error.new("remote_not_found", "Git remote #{remote.inspect} is not configured in the current checkout")
      end

      output, _error, status = capture("config", "--get-all", "remote.#{remote}.url")
      urls = status.success? ? output.lines(chomp: true) : []
      raise Error.new("remote_url_missing", "Git remote #{remote.inspect} has no URL") if urls.empty?
      if urls.length > 1
        raise Error.new("remote_url_ambiguous", "Git remote #{remote.inspect} has multiple URLs; configure exactly one")
      end

      urls.first
    rescue Errno::ENOENT
      raise Error.new("git_unavailable", "Git executable is not available")
    end

    private

    def git(*arguments)
      output, error, status = capture(*arguments)
      return [ output, error ] if status.success?

      raise Error.new("not_a_checkout", "current directory is not inside a Git working tree")
    end

    def capture(*arguments)
      Open3.capture3(@environment, "git", "-C", @working_directory.to_s, *arguments)
    end
  end
end
