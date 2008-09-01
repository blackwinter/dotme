begin
  require 'wirble'

  # save history newest-first, instead of default oldest-first
  class Wirble::History
    def save_history
      return unless Object.const_defined?(:IRB)

      path, max_size, perms = %w[path size perms].map { |v| cfg(v) }

      # read lines from history, and truncate the list (if necessary)
      lines = Readline::HISTORY.to_a.reverse.uniq.reverse
      lines = lines[-max_size..-1] if lines.size > max_size

      # write the history file
      real_path = File.expand_path(path)
      File.open(real_path, perms) { |fh| fh.puts lines }
      say 'Saved %d lines to history file %s.' % [lines.size, path]
    end
  end

  # make wirble and ruby-debug use the same histfile
  FILE_HISTORY = Wirble::History::DEFAULTS[:history_path]

  # start wirble (with color)
  Wirble.init(:skip_prompt => true)
  Wirble.colorize
rescue LoadError => err
  warn "#{err} (in #{__FILE__}:#{__LINE__})"
end
