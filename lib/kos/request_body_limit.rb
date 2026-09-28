require "stringio"

module Kos
  class RequestBodyLimit
    def initialize(app, max_bytes:)
      @app = app
      @max_bytes = max_bytes
    end

    def call(env)
      input = env["rack.input"]
      return @app.call(env) unless input

      body = +""
      while (chunk = input.read(64.kilobytes))
        break if chunk.empty?

        body << chunk
        return too_large if body.bytesize > @max_bytes
      end
      env["rack.input"] = StringIO.new(body)
      @app.call(env)
    end

    private

    def too_large
      response = { error: "request_too_large", message: "request body must be at most 8 MiB" }.to_json
      [ 413, { "content-type" => "application/json", "content-length" => response.bytesize.to_s }, [ response ] ]
    end
  end
end
