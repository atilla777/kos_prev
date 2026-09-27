require "pathname"

data_home = ENV.fetch("KOS_DATA_HOME")
abort "KOS_DATA_HOME must be an absolute path" unless Pathname.new(data_home).absolute?

puts File.join(File.expand_path(data_home), "worktrees", Integer(ARGV.fetch(0), 10).to_s,
  Integer(ARGV.fetch(1), 10).to_s)
