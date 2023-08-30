module Http
  class MethodRouter

    attr_reader :request, :response, :params, :env

    def call(env)
      self.dup.call!(env)
    end

    def call!(env)
      env["PATH_INFO"] = "/" if env["PATH_INFO"].empty?

      catch(:halt) do
        init_req(env)

        meth = @request.request_method.downcase.to_sym
        halt 405 unless respond_to? meth

        begin
          before_req
          body = method(meth).()
          body = [body] unless body.respond_to? :each
          @response.body = body
        rescue MalformedRequestError => ex
          halt 400, "malformed request: #{ex}"
        end
      end

      after_req
      @response.finish
    end

    def init_req(env)
      @request  = Rack::Request.new(env)
      @response = Rack::Response.new
      @params   = request.params
      @env      = env
    end

    def before_req; end
    def after_req; end

    def halt(*res)
      response.status = res.detect { |x| x.is_a?(Integer) } || 200
      response.headers.merge!(res.detect { |x| x.is_a?(Hash) } || {})
      response.body = [res.detect { |x| x.is_a?(String) } || ""]
      throw :halt, response
    end

  end
end
