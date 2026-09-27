require "fileutils"

unless Rails.env.test?
  Rails.application.config.x.kos.api_token =
    Kos::Configuration.validate_api_token!(Rails.application.config.x.kos.api_token)
  data_home = Rails.application.config.x.kos.data_home
  Kos::Configuration.validate_data_home!(data_home, repository_root: Rails.root)
  FileUtils.mkdir_p(data_home)
end
