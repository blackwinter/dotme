#--
###############################################################################
#                                                                             #
# dotme - The dotfile manager                                                 #
#                                                                             #
# Copyright (C) 2008-2016 Jens Wille                                          #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@gmail.com>                                       #
#                                                                             #
# dotme is free software; you can redistribute it and/or modify it under the  #
# terms of the GNU Affero General Public License as published by the Free     #
# Software Foundation; either version 3 of the License, or (at your option)   #
# any later version.                                                          #
#                                                                             #
# dotme is distributed in the hope that it will be useful, but WITHOUT ANY    #
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS   #
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for     #
# more details.                                                               #
#                                                                             #
# You should have received a copy of the GNU Affero General Public License    #
# along with dotme. If not, see <http://www.gnu.org/licenses/>.               #
#                                                                             #
###############################################################################
#++

require 'pathname'
require 'fileutils'

%w[rdoc/task nuggets/env/user_home nuggets/file/which].each { |lib|
  begin
    require lib
  rescue LoadError
  end
}

if Dir.pwd != dir = File.dirname(__FILE__)
  abort "Please change into directory `#{dir}' and run again."
end

# {{{ module DotMe

# Manage dotfiles.

module DotMe

  extend self

  VERSION = '0.2.0'

  IGNORE = %w[Rakefile.rb README COPYING .gitignore inclexcl.sample]

  HOME = ENV.respond_to?(:user_home) ?
    ENV.user_home : ENV['HOME'] || File.expand_path('~')

  HAVE_GIT = File.respond_to?(:which) ?
    File.which('git') : !%x{git --help}.empty?

  # {{{ class Status

  # Statuses for managed dotfiles.

  class Status

    STATUSES = Hash.new { |h, k| h[k] = k ? new(k) : h[:UNKNOWN] }

    class << self

      def [](status)
        status.is_a?(Status) ? status : STATUSES[status]
      end

    end

    attr_reader :status

    def initialize(status)
      @status = status
    end

    def to_s
      status.to_s.tr('_', ' ')
    end

    def ===(other)
      other === status
    end

  end

  class ::Symbol

    alias_method :_dotme_original_threequal, :===

    def ===(other)
      if other.is_a?(Status)
        other.status == self
      else
        _dotme_original_threequal(other)
      end
    end

  end

  # }}}

  def install
    symlinks.each { |target, symlink|
      dryrun(:symlink, target, symlink) {
        status, actual = status_for(symlink, target)

        begin
          File.symlink(target, symlink)
          puts "[ADDED] #{symlink} -> #{target}"
        rescue Errno::EEXIST => err
          warn "[ERROR=#{status}] #{err}"
        end
      }
    }
  end

  def update
    with_clean_working_directory do
      if out = git(:update) and git(:fetch)
        out.lines.grep(/^Updating\s+(\S+)/) {
          puts git(:log, '--oneline', '--reverse', $1) }
      end
    end

    install
  end

  def status
    puts git(:status)
    puts

    symlinks.each { |target, symlink|
      status, actual = status_for(symlink, target)
      msg = "[#{status}] #{symlink}"

      case status
        when :MISMATCH
          msg << ':' << "\n  expected: #{target}" <<
                        "\n  got:      #{actual}"
        else
          msg << " -> #{target}"
      end

      puts msg
    }
  end

  def uninstall
    symlinks.each { |target, symlink|
      dryrun(:unlink, symlink) {
        status, actual = status_for(symlink, target)

        case status
          when :UNTRACKED
            warn "[ERROR=#{status}] Not removing '#{symlink}' - NOT A SYMLINK"
          when :NOT_FOUND
            warn "[ERROR=#{status}] Not removing '#{symlink}' - NOT FOUND"
          when :MISMATCH
            warn "[ERROR=#{status}] Not removing symlink '#{symlink}' - targets don't match:"
            warn "  expected: #{target}"
            warn "  got:      #{actual}"
          when :TRACKED
            begin
              File.unlink(symlink)
              puts "[REMOVED] #{symlink} -> #{target}"
            rescue Errno::ENOENT => err
              warn "[ERROR] #{err}"
            end
          else
            warn "[ERROR=#{status}] #{symlink}"
        end
      }
    }
  end

  def reset(ask = true)
    abort unless agreed?('This will undo all your local modifications (untracked files are kept).') if ask
    git(:reset)
  end

  def pristine
    abort unless agreed?('This will undo all your local modifications AND remove all untracked files.')
    reset(false)

    git(:untracked).split("\0").sort.each { |file|
      dryrun(:rm_r, file) {
        FileUtils.rm_r(file)
        puts "[REMOVED] #{file}"
      }
    }
  end

  def symlinks
    hash = {}

    dotfiles.each { |path|
      parts   = path.split(File::SEPARATOR)
      target  = File.join(parts[0..1])
      symlink = File.join(HOME, ".#{parts[1] || parts[0]}")

      hash[File.expand_path(target)] = symlink
    }

    hash.sort
  end

  def dotfiles
    files = inclexcl(git(:tracked).split("\0") - IGNORE)
    custom = []

    files.each { |file|
      if File.readable?(mine = "#{file}.mine")
        custom << mine
      end
    }

    files + custom
  end

  # {{{ Utility methods

  private

  def status_for(symlink, target)
    if File.symlink?(symlink)
      if File.exists?(target)
        actual = Pathname.new(File.readlink(symlink)).realpath.to_s
        status = target == actual ? :TRACKED : :MISMATCH
      else
        status = :MISSING
      end
    else
      if File.exists?(symlink)
        status = File.exists?(target) ? :ALIEN : :UNTRACKED
      else
        status = File.exists?(target) ? :NOT_FOUND : :UNTRACKED
      end
    end

    [Status[status], actual]
  end

  def with_clean_working_directory
    git(:stash)
    yield
  ensure
    git(:unstash)
  end

  def git(cmd, *args)
    abort "Please install `git'." unless HAVE_GIT

    # aliases
    case cmd
      when :update
        cmd = 'pull'
        args << 'origin' << 'master'
      when :reset
        cmd = 'checkout'
        args << '-f'
      when :stash
        cmd = 'stash'
        args << 'save'
      when :unstash
        cmd = 'stash'
        args << 'pop'
      when :tracked
        cmd = 'ls-files'
        args << '-z'
        _return = %w[foo/x foo/y bar/y bar/z/a bar/z/b].join("\0")
      when :untracked
        cmd = 'ls-files'
        args << '-z' << '-o' << '--directory'
        _return = %w[foo/x.mine bar/y.mine blah].join("\0")
    end

    dryrun(:git, cmd, *args + [:_return => _return]) {
      %x{git #{[cmd, *args].join(' ')}}
    }
  end

  def inclexcl(files)
    if File.readable?(inclexcl = 'inclexcl')
      incl, excl, replace = [], [], false

      File.foreach(inclexcl) { |pattern|
        pattern.sub!(/\A\s*/, '')
        pattern.sub!(/\s*\z/, '')
        next if pattern.empty?

        pattern.sub!(/\A([#+-])/, '')
        prefix = $1 # save capture
        next if prefix == '#'

        pattern.sub!(/\/\z/, '')
        if pattern.count('/') > 1
          warn "[ERROR] Illegal pattern - #{pattern}"
          next
        end

        matches = files.grep(glob2re(pattern))

        if prefix == '-'
          excl += matches
        else
          replace = true
          incl += matches
        end
      }

      files  = incl if replace
      files -= excl
    end

    files.uniq
  end

  def glob2re(pattern)
    %r{
      \A
      #{
        pattern.
          gsub(/\?/, '.').
          gsub(/\*/, '.*?')
      }
      (?:/|\z)
    }x
  end

  def agree(msg)
    print "#{msg} (yes/no) "

    case $stdin.gets.chomp[0].downcase
      when 'y' then true
      when 'n' then false
      else
        puts 'Please enter "[y]es" or "[n]o".'
        agree(msg)
    end
  rescue Interrupt
    abort ''
  end

  def agreed?(msg)
    puts msg
    agree('Are you sure you want that?') && agree('Are you REALLY sure?')
  end

  def dryrun(what, *args)
    if ENV['DRYRUN']
      _return = args.last.delete(:_return) if args.last.is_a?(Hash)
      warn ['[DRYRUN]', what, *args].join(' ')
      _return
    else
      yield
    end
  end

  # }}}

end

# }}}

task default: :update

desc "Install symlinks to dotfiles."
task :install do
  DotMe.install
end

desc "Update codebase and symlinks."
task :update do
  DotMe.update
end

desc "Report status information about codebase and symlinks."
task :status do
  DotMe.status
end

desc "Revert local modifications."
task :reset do
  DotMe.reset
end

desc "Reset codebase to its original state."
task :pristine do
  DotMe.pristine
end

desc "Remove symlinks to dotfiles."
task :uninstall do
  DotMe.uninstall
end

if Object.const_defined?(:RDoc)
  rdoc_task = RDoc::Task.new(:doc) { |t|
    t.rdoc_dir   = 'doc'
    t.rdoc_files = %w[README COPYING Rakefile.rb]
    t.options    = [
      '--title', "dotme Application documentation (v#{DotMe::VERSION})",
      '--main', 'README', '--charset', 'UTF-8', '--line-numbers', '--all'
    ]
  }

  desc "Publish RDoc documentation"
  task 'doc:publish' => :doc do
    remote = %x{git branch -r}[%r{(\S+)/#{Regexp.escape(branch = 'gh-pages')}$}, 1]
    url    = %x{git remote -v}[%r{^#{Regexp.escape(remote)}\s+(\S+)}, 1]

    rm_rf dir = ".#{branch}"

    sh 'git', 'clone', '-n', '-o', remote, url, dir

    Dir.chdir(dir) {
      sh 'git', 'checkout', '-b', branch, "#{remote}/#{branch}"

      cp_r Dir["../#{rdoc_task.rdoc_dir}/*"], '.'

      sh 'git', 'add', '.'
      sh 'git', 'commit', '-m', 'Updated documentation.'
      sh 'git', 'push', remote, branch
    }
  end
end

# vim:ft=ruby:fdm=marker:fen
