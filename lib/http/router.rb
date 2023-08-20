require 'nancy'

module Http
    class Router < Nancy::Base

        def call!(env)
            env["PATH_INFO"] = "/" if env["PATH_INFO"].empty?

            @request  = Rack::Request.new(env)
            @response = Rack::Response.new
            @params   = request.params
            @env      = env

            method_eval

            @response.finish
        end

        private

        def method_eval
            catch(:halt) do
                meth = @request.request_method.downcase.to_sym
                halt 405 unless self.respond_to? meth

                return action_eval(method(meth).to_proc)
            end
        end

    end
end