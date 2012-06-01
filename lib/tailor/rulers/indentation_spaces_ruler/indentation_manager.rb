require_relative '../../ruler'
require_relative '../../logger'
require_relative '../../lexer/lexer_constants'

class Tailor
  module Rulers
    class IndentationSpacesRuler < Tailor::Ruler

      # Used for managing the state of indentation for some file/text.  An
      # object of this type has no knowledge of the file/text itself, but rather
      # just manages indentation expectations based on the object's user's
      # input, somewhat like a state machine.
      #
      # For the sake of talking about indentation expectations, the docs here
      # make mention of 'levels' of indentation.  A _level_ here is simply
      # 1 * (number of spaces to indent); so if you've set (number of spaces to
      # indent) to 2, saying something should be indented 1 level, is simply
      # saying that it should be indented 2 spaces.
      class IndentationManager
        include Tailor::LexerConstants
        include Tailor::Logger::Mixin

        # These are event names generated by the {Lexer} that signify
        # indentation level should/could increase by 1.
        ENCLOSERS = Set.new [:on_lbrace, :on_lbracket, :on_lparen]

        # Look-up table that allows for <tt>OPEN_EVENT_FOR[:on_rbrace]</tt>.
        OPEN_EVENT_FOR = {
          on_kw: :on_kw,
          on_rbrace: :on_lbrace,
          on_rbracket: :on_lbracket,
          on_rparen: :on_lparen
        }

        # Allows for updating the indent expectation for the current line.
        attr_accessor :amount_to_change_this

        # @return [Fixnum] The actual number of characters the current line is
        #   indented.
        attr_reader :actual_indentation

        # @return [Array<Hash>] Each element represents a reason why code should
        #   be indented.  Indent levels are not necessarily 1:1 relationship
        #   to these reasons (hence the need for this class).
        attr_reader :indent_reasons

        # @param [Fixnum] spaces The number of spaces each level of indentation
        #   should move in & out.
        def initialize(spaces)
          @spaces = spaces
          @proper = { this_line: 0, next_line: 0 }
          @actual_indentation = 0
          @indent_reasons = []
          @amount_to_change_this = 0

          start
        end

        # @return [Fixnum] The indent level the file should currently be at.
        def should_be_at
          @proper[:this_line]
        end

        # Decreases the indentation expectation for the current line by
        # 1 level.
        def decrease_this_line
          if started?
            @proper[:this_line] -= @spaces

            if @proper[:this_line] < 0
              @proper[:this_line] = 0
            end

            log "@proper[:this_line] = #{@proper[:this_line]}"
            log "@proper[:next_line] = #{@proper[:next_line]}"
          else
            log "#decrease_this_line called, but checking is stopped."
          end
        end

        # Sets up expectations in +@proper+ based on the number of +/- reasons
        # to change this and next lines, given in +@amount_to_change_this+.
        def set_up_line_transition
          log "Amount to change this line: #{@amount_to_change_this}"
          decrease_this_line if @amount_to_change_this < 0
        end

        # Should be called just before moving to the next line.  This sets the
        # expectation set in +@proper[:next_line]+ to
        # +@proper[:this_line]+.
        def transition_lines
          if started?
            log "Resetting change_this to 0."
            @amount_to_change_this = 0
            log "Setting @proper[:this_line] = that of :next_line"
            @proper[:this_line] = @proper[:next_line]
            log "Transitioning @proper[:this_line] to #{@proper[:this_line]}"
          else
            log "Skipping #transition_lines; checking is stopped."
          end
        end

        # Starts the process of increasing/decreasing line indentation
        # expectations.
        def start
          log "Starting indentation ruling."
          log "Next check should be at #{should_be_at}"
          @do_measurement = true
        end

        # Tells if the indentation checking process is on.
        #
        # @return [Boolean] +true+ if it's started; +false+ if not.
        def started?
          @do_measurement
        end

        # Stops the process of increasing/decreasing line indentation
        # expectations.
        def stop
          if started?
            msg = "Stopping indentation ruling.  Should be: #{should_be_at}; "
            msg << "actual: #{@actual_indentation}"
            log msg
          end

          @do_measurement = false
        end

        # Updates +@actual_indentation+ based on the given lexed_line_output.
        #
        # @param [Array] lexed_line_output The lexed output for the current line.
        def update_actual_indentation(lexed_line_output)
          if lexed_line_output.end_of_multi_line_string?
            log "Found end of multi-line string."
            return
          end

          first_non_space_element = lexed_line_output.first_non_space_element
          @actual_indentation = first_non_space_element.first.last
          log "Actual indentation: #{@actual_indentation}"
        end

        # Checks if the current line ends with an operator, comma, or period.
        #
        # @param [LexedLine] lexed_line
        # @return [Boolean]
        def line_ends_with_single_token_indenter?(lexed_line)
          lexed_line.ends_with_op? ||
            lexed_line.ends_with_comma? ||
            lexed_line.ends_with_period? ||
            lexed_line.ends_with_label? ||
            lexed_line.ends_with_modifier_kw?
        end

        # Checks to see if the last token in @single_tokens is the same as the
        # one in +token_event+.
        #
        # @param [Array] token_event A single event (probably extracted from a
        #   {LexedLine}).
        # @return [Boolean]
        def line_ends_with_same_as_last(token_event)
          return false if @indent_reasons.empty?

          @indent_reasons.last[:event_type] == token_event[1]
        end

        # Determines if the current spot in the file is enclosed in braces,
        # brackets, or parens.
        #
        # @return [Boolean]
        def in_an_enclosure?
          return false if @indent_reasons.empty?

          i_reasons = @indent_reasons.dup
          log "i reasons: #{i_reasons}"

          until ENCLOSERS.include? i_reasons.last[:event_type]
            i_reasons.pop
            break if i_reasons.empty?
          end

          return false if i_reasons.empty?

          i_reasons.last[:event_type] == :on_lbrace ||
            i_reasons.last[:event_type] == :on_lbracket ||
            i_reasons.last[:event_type] == :on_lparen
        end

        # Adds to the list of reasons to indent the next line, then increases
        # the expectation for the next line by +@spaces+.
        #
        # @param [Symbol] event_type The event type that caused the reason for
        #   indenting.
        # @param [Tailor::Token,String] token The token that caused the reason
        #   for indenting.
        # @param [Fixnum] lineno The line number the reason for indenting was
        #   discovered on.
        def add_indent_reason(event_type, token, lineno)
          @indent_reasons << {
            event_type: event_type,
            token: token,
            lineno: lineno,
            should_be_at: @proper[:this_line]
          }

          @proper[:next_line] = @indent_reasons.last[:should_be_at] + @spaces
          log "Added indent reason; it's now:"
          @indent_reasons.each { |r| log r.to_s }
        end

        # An "opening reason" is a reason for indenting that also has a "closing
        # reason", such as a +def+, +{+, +[+, +(+.
        #
        # @param [Symbol] event_type The event type that is the opening reason.
        # @param [Tailor::Token,String] token The token that is the opening
        #   reasons.
        # @param [Fixnum] lineno The line number the opening reason was found
        #   on.
        def update_for_opening_reason(event_type, token, lineno)
          if token.modifier_keyword?
            log "Found modifier in line: '#{token}'"
            return
          end

          log "Token '#{token}' not used as a modifier."

          if token.do_is_for_a_loop?
            log "Found keyword loop using optional 'do'"
            return
          end

          add_indent_reason(event_type, token, lineno)
        end

        # A "continuation reason" is a reason for indenting & outdenting that's
        # not an opening or closing reason, such as +elsif+, +rescue+, +when+
        # (in a +case+ statement), etc.
        #
        # @param [Symbol] event_type The event type that is the opening reason.
        # @param [Tailor::LexedLine] lexed_line
        # @param [Fixnum] lineno The line number the opening reason was found
        #   on.
        def update_for_continuation_reason(token, lexed_line, lineno)
          d_tokens = @indent_reasons.dup
          d_tokens.pop
          on_line_token = d_tokens.find { |t| t[:lineno] == lineno }
          log "online token: #{on_line_token}"

          if on_line_token.nil? && lexed_line.to_s =~ /^\s*#{token}/
            @proper[:this_line] -= @spaces unless @proper[:this_line].zero?
            msg = "Continuation keyword: '#{token}'.  "
            msg << "change_this -= 1 -> #{@proper[:this_line]}"
            log msg
          end

          last_reason_line = @indent_reasons.find { |r| r[:lineno] == lineno }

          @proper[:next_line] = if last_reason_line.nil?
            if @indent_reasons.empty?
              @spaces
            else
              @indent_reasons.last[:should_be_at] + @spaces
            end
          else
            @indent_reasons.last[:should_be_at] - @spaces
          end
        end

        # A "closing reason" is a reason for indenting that also has an "opening
        # reason", such as a +end+, +}+, +]+, +)+.
        #
        # @param [Symbol] event_type The event type that is the closing reason.
        # @param [Tailor::Token,String] token The token that is the closing
        #   reason.
        def update_for_closing_reason(event_type, lexed_line)
          remove_continuation_keywords
          remove_appropriate_reason(event_type)

          @proper[:next_line] = if @indent_reasons.empty?
            0
          else
            @indent_reasons.last[:should_be_at] + @spaces
          end

          log "Updated :next after closing; it's now #{@proper[:next_line]}"

          meth = "only_#{event_type.to_s.sub("^on_", '')}?"

          if lexed_line.send(meth.to_sym) || lexed_line.to_s =~ /^\s*end\n?$/
            @proper[:this_line] = @proper[:this_line] - @spaces
            msg = "End multi-line statement. "
            msg < "change_this -= 1 -> #{@proper[:this_line]}."
            log msg
          end
        end

        # Removes the last matching opening reason reason of +event_type+ from
        # the list of indent reasons.
        #
        # @param [Symbol] closing_event_type The closing event for which to find
        #   the matching opening event to remove from the list of indent
        #   reasons.
        def remove_appropriate_reason(closing_event_type)
          if last_opening_event = last_opening_event(closing_event_type)
            r_index = @indent_reasons.reverse.index(last_opening_event)
            index = @indent_reasons.size - r_index - 1
            tmp_reasons = []

            @indent_reasons.each_with_index do |r, i|
              tmp_reasons << r unless i == index
            end

            @indent_reasons.replace(tmp_reasons)
          elsif last_single_token_event
            log "Just popped off reason: #{@indent_reasons.pop}"
          else
            log "Couldn't find a matching opening reason to pop off...'"
            return
          end

          log "Removed indent reason; it's now:"
          @indent_reasons.each { |r| log r.to_s }
        end

        # A "single-token" event is one that that causes indentation
        # expectations to increase. They don't have have a paired closing
        # reason like opening reasons.  Instead, they're determined to be done
        # with their indenting when an :on_ignored_nl occurs.  Single-token
        # events are operators and commas (commas that aren't used as
        # separators in {, [, ( events).
        def last_single_token_event
          return nil if @indent_reasons.empty?

          @indent_reasons.reverse.find do |r|
            !ENCLOSERS.include?(r[:event_type]) && r[:event_type] != :on_kw
          end
        end


        # Returns the last matching opening event that corresponds to the
        # +closing_event_type+.
        #
        # @param [Symbol] closing_event_type The closing event for which to
        #   find its associated opening event.
        def last_opening_event(closing_event_type)
          return nil if @indent_reasons.empty?

          @indent_reasons.reverse.find do |r|
            r[:event_type] == OPEN_EVENT_FOR[closing_event_type]
          end
        end

        def last_indent_reason_type
          return if @indent_reasons.empty?

          @indent_reasons.last[:event_type]
        end

        # Removes all continuation keywords from the list of
        # indentation reasons.
        def remove_continuation_keywords
          return if @indent_reasons.empty?

          while CONTINUATION_KEYWORDS.include?(@indent_reasons.last[:token])
            log "Just popped off continuation reason: #{@indent_reasons.pop}"
          end
        end

        # Overriding to be able to call +#multi_line_brackets?+,
        # +#multi_line_braces?+, and +#multi_line_parens?+, where each takes a
        # single parameter, which is the lineno.
        #
        # @return [Boolean]
        def method_missing(meth, *args, &blk)
          if meth.to_s =~ /^multi_line_(.+)\?$/
            token = case $1
            when "brackets" then '['
            when "braces" then '{'
            when "parens" then '('
            else
              super(meth, *args, &blk)
            end

            lineno = args.first

            tokens = @indent_reasons.find_all do |t|
              t[:token] == token
            end

            log "#{meth} called, but no #{$1} were found." if tokens.empty?
            return false if tokens.empty?

            token_on_this_line = tokens.find { |t| t[:lineno] == lineno }
            return true if token_on_this_line.nil?

            false
          else
            super(meth, *args, &blk)
          end
        end
      end
    end
  end
end
