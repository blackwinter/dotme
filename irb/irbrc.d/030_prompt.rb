class IRB::Context
  %w[prompt_i prompt_s prompt_c prompt_n return_format].each { |name|
    define_method(name) {
      ivar = instance_variable_get("@#{name}")
      ivar.respond_to?(:call) ? ivar['%.4f' % @runtime] : ivar
    }
  }

  alias_method :_irbrc_original_evaluate, :evaluate

  def evaluate(line, line_no)
    @runtime = Benchmark.realtime { _irbrc_original_evaluate(line, line_no) }
  end
end

IRB.conf[:PROMPT] ||= {}  # prevent error in webrick

# my prompt ;-)
IRB.conf[:PROMPT][:MY_PROMPT] = {               # name of prompt mode
  :PROMPT_I => '  ',                            # normal prompt
  :PROMPT_S => '  ',                            # prompt for continuing strings
  :PROMPT_C => '  ',                            # prompt for continuing statement
  :RETURN   => lambda { |rt| "#{rt} => %s\n" }  # format to return value
}
IRB.conf[:PROMPT_MODE] = :MY_PROMPT
