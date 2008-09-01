# rails settings (cf. <http://www.quotedprintable.com/2007/9/13/my-irbrc>)
if rails_env = ENV['RAILS_ENV']
  # prompt
  hint = rails_env == 'development' ? '' : "@#{rails_env}"

  if svn_info = YAML.load(`svn info`)
    path = svn_info['URL'].sub(%r{#{Regexp.escape(svn_info['Repository Root'])}/?}, '')

    prompt = File.basename(svn_info['Repository Root']) << hint
    prompt << " [#{path}]" unless path.empty?
  else
    prompt = File.basename(Dir.pwd) << hint
  end

  # add "ENV['RAILS_SANDBOX'] = 'true'" in rails-X.X.X/lib/commands/console.rb
  prompt << (ENV['RAILS_SANDBOX'] ? '>' : '$') << ' '

  IRB.conf[:PROMPT][:RAILS] = {
    :PROMPT_I => prompt,
    :PROMPT_S => prompt,
    :PROMPT_C => prompt,
    :RETURN   => IRB.conf[:PROMPT][:MY_PROMPT][:RETURN]
  }
  IRB.conf[:PROMPT_MODE] = :RAILS

  # logger
  unless Object.const_defined?(:RAILS_DEFAULT_LOGGER)
    begin
      require 'logger'
      Object.const_set(:RAILS_DEFAULT_LOGGER, Logger.new(STDOUT))
    rescue LoadError => err
      warn "#{err} (in #{__FILE__}:#{__LINE__})"
    end
  end

  # called after the irb session is initialized and rails has been loaded
  IRB.conf[:IRB_RC] = lambda { |context|
    Object.instance_eval {
      define_method(:logger) { |*args|
        if args.empty?
          RAILS_DEFAULT_LOGGER
        else
          level, previous_level = args.first, logger.level

          logger.level = level.is_a?(Integer) ? level : Logger.const_get(level.to_s.upcase)

          previous_level
        end
      }
    }
  }
end
