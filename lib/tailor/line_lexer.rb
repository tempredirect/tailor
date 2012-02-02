require 'ripper'

class Tailor

  # https://github.com/svenfuchs/ripper2ruby/blob/303d7ac4dfc2d8dbbdacaa6970fc41ff56b31d82/notes/scanner_events
  class LineLexer < Ripper::Lexer
    KEYWORDS_TO_INDENT = [
      :class, :module, :def, :if, :elsif, :else, :do, :when, :begin, :rescue,
      :ensure, :case, :while
    ]
    CONTINUATION_KEYWORDS = [
      :elsif, :else, :when, :rescue, :ensure
    ]

    attr_reader :indentation_tracker
    attr_accessor :problems


    # @param [String] file_name The name of the file to read and analyze.
    def initialize(file_name)
      @file_name = file_name
      file_text = File.open(@file_name, 'r').read

      Tailor.log "Setting @proper_indentation[:this_line] to 0."
      @proper_indentation = {}
      @proper_indentation[:this_line] = 0
      @proper_indentation[:next_line] = 0
      @problems = []

      @config = Tailor.config[:indentation]
      super file_text
    end

    def log(*args)
      args.first.insert(0, "#{lineno}: ")
      Tailor.log(*args)
    end

    # This is the first thing that exists on a new line--NOT the last!
    def on_nl(token)
      log "#on_nl"

      # check indentation
      c = current_lex(super)
      indentation = current_line_indent(c)
      if indentation != @proper_indentation[:this_line]
        message = "ERRRRORRRROROROROR! column (#{indentation}) != proper indent (#{@proper_indentation[:this_line]})"
        log message
        @problems << { file_name: @file_name, type: :indentation, line: lineno, message: message }
      end

      # prep for next line
      log "Setting @proper_indentation[:this_line] = that of :next_line"
      @proper_indentation[:this_line] = @proper_indentation[:next_line]
      log "transitioning @proper_indentation[:this_line] to #{@proper_indentation[:this_line]}"
    end

    # @param [Array] lexed_output The lexed output for the whole file.
    # @return [Array]
    def current_lex(lexed_output)
      log "#current_line.  Line: #{self.lineno}"

      lexed_output.find_all { |token| token.first.first == lineno }
    end

    # @return [Fixnum] Number of the first non-space (:on_sp) token.
    def current_line_indent(lexed_line_output)
      first_non_space_element = lexed_line_output.find { |e| e[1] != :on_sp }
      first_non_space_element.first.last
    end

    def on_ignored_nl(token)
      log "#on_ignored_nl.  Ignoring line #{lineno}."
      #@current_line_lexed = current_lex(super)
      @proper_indentation[:this_line] = @proper_indentation[:next_line]
      log "@proper_indentation[:this_line] = #{@proper_indentation[:this_line]}"
      log "@proper_indentation[:next_line] = #{@proper_indentation[:next_line]}"
    end

    def on_kw(token)
      log "#on_kw. token: #{token}.  token class: #{token.class}"

      if KEYWORDS_TO_INDENT.include?(token.to_sym)
        log "indent keyword found: #{token}"

        if CONTINUATION_KEYWORDS.include? token.to_sym
          @proper_indentation[:this_line] -= @config[:spaces]
        else
          @proper_indentation[:next_line] += @config[:spaces]
        end

        log "@proper_indentation[:next_line] = #{@proper_indentation[:next_line]}"
      end

      if token == "end"
        log "outdent keyword found: end"
        @proper_indentation[:this_line] -= @config[:spaces]
        @proper_indentation[:next_line] -= @config[:spaces]
        log "@proper_indentation[:this_line] = #{@proper_indentation[:this_line]}"
        log "@proper_indentation[:next_line] = #{@proper_indentation[:next_line]}"
      end

      log "@proper_indentation[:this_line]: #{@proper_indentation[:this_line]}"
      log "@proper_indentation[:next_line]: #{@proper_indentation[:next_line]}"

      super(token)
    end

    def on_lbracket(token)
      log "#on_lbracket"
      @bracket_start_line = lineno
      @proper_indentation[:next_line] += @config[:spaces]
      log "@proper_indentation[:next_line] = #{@proper_indentation[:next_line]}"
      super(token)
    end

    def on_rbracket(token)
      log "#on_rbracket"

      if multiline_brackets?
        @proper_indentation[:this_line] -= @config[:spaces]
      end

      @proper_indentation[:next_line] -= @config[:spaces]
      log "@proper_indentation[:next_line] = #{@proper_indentation[:next_line]}"
      super(token)
    end

    def on_lbrace(token)
      log "#on_lbrace"
      @brace_start_line = lineno
      @proper_indentation[:next_line] += @config[:spaces]
      log "@proper_indentation[:next_line] = #{@proper_indentation[:next_line]}"
      super(token)
    end

    def on_rbrace(token)
      log "#on_rbrace"

      if multiline_braces?
        @proper_indentation[:this_line] -= @config[:spaces]
      end

      @proper_indentation[:next_line] -= @config[:spaces]
      log "@proper_indentation[:next_line] = #{@proper_indentation[:next_line]}"
      super(token)
    end

    def multiline_braces?
      @brace_start_line < lineno
    end

    def multiline_brackets?
      @bracket_start_line < lineno
    end
  end
end
