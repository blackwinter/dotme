###############################################################################
# A component of dotme, the dotfile manager.                                  #
###############################################################################

begin
  regexp  = ENV['WATCH_FOR_ADDED_METHODS']
  klasses = ENV['WATCH_FOR_ADDED_METHODS_IN']

  if regexp || klasses
    if regexp == 'true'
      require 'nuggets/util/added_methods/init'
    else
      regexp  = Regexp.new(regexp || '')
      klasses = (klasses || '').split

      require 'nuggets/util/added_methods'
      AddedMethods.init(regexp, klasses)
    end
  end
rescue LoadError => err
  warn "#{err} (in #{__FILE__}:#{__LINE__})"
end
