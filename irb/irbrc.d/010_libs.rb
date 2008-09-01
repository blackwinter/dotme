# load libraries
%w[
  yaml
  tempfile
  benchmark
  what_methods

  utility_belt/interactive_editor
  utility_belt/irb_verbosity_control
  utility_belt/language_greps
].each { |lib|
  begin
    require lib
  rescue LoadError => err
    warn "#{err} (in #{__FILE__}:#{__LINE__})"
  end
}
