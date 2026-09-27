require_relative "lib/kos/version"

Gem::Specification.new do |spec|
  spec.name = "kos"
  spec.version = Kos::VERSION
  spec.authors = [ "KOS contributors" ]
  spec.summary = "HTTP command-line client for the KOS task coordination service"
  spec.description = "A thin command-line client for administering and executing KOS task workflows."
  spec.homepage = "https://github.com/atilla777/kos"
  spec.required_ruby_version = ">= 3.4.0"

  spec.files = %w[README.md bin/kos lib/kos/api_token.rb lib/kos/cli.rb lib/kos/version.rb]
  spec.bindir = "bin"
  spec.executables = [ "kos" ]
  spec.require_paths = [ "lib" ]

  spec.metadata = {
    "source_code_uri" => "https://github.com/atilla777/kos",
    "rubygems_mfa_required" => "true"
  }
end
