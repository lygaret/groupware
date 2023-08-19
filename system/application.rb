require 'dry/system'

$LOAD_PATH << Pathname.new(__dir__) / '..'
$LOAD_PATH << Pathname.new(__dir__) / '..' / 'lib'

class Application < Dry::System::Container
    use :env, inferrer: -> { ENV.fetch('RACK_ENV', :development).to_sym }
    use :logging
    use :monitoring

    configure do |config|
        config.root = Pathname.new(__dir__) / '..'
        config.component_dirs.add 'system/components'
    end
end