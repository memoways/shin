
require 'shin/ast'
require 'shin/mutator'
require 'shin/utils'

module Shin
  class Parser
    DEBUG = ENV['PARSER_DEBUG']

    include Shin::Utils::LineColumn
    include Shin::Utils::Snippet
    include Shin::Utils::Mangler
    include Shin::AST

    class Error < StandardError; end
    class EOF < Error; end
    
    attr_reader :input

    NUMBER_RE = /[0-9]+/
    OPEN_MAP = {
      '(' => List,
      '[' => Vector,
      '{' => Map,
    }

    CLOS_REV_MAP = {
      List    => ')',
      Vector  => ']',
      Map     => '}',
      Set     => '}',
      Closure => ')',
    }

    def self.parse(source)
      # parse is a no-op if source is not a String.
      # it might be a piece of already-parsed AST.
      return source unless ::String === source
      Shin::Parser.new(source).parse
    end

    def self.parse_file(path)
      Shin::Parser.new(File.read(path), :file => path).parse
    end

    def initialize(input, options = {})
      @options = options.dup

      case
      when input.respond_to?(:each_char)
        @input = input.freeze
      when input.respond_to?(:to_str)
        require 'stringio' unless defined?(StringIO)
        @input = input.to_str.freeze
      else
        raise ArgumentError, "expected an IO or String input stream, but got #{input.inspect}"
      end
    end

    def parse
      nodes = []
      heap  = Hamster.deque(nodes)
      state = Hamster.deque(:expr)

      @pos = 0
      @input.each_char do |c|
        if DEBUG
          puts "#{c} at #{@pos}\t<- #{state}"
          puts "      \t<- [#{heap.join(", ")}]"
          puts
        end

        case state.last
        when :expr, :expr_one
          state = state.pop if state.last == :expr_one

          case c
          when ' ', "\t", "\n", ','
            # muffin
          when '@'
            heap   = heap  << Deref       << token     << []
            state  = state << :close_one  << :expr_one
          when '`'
            heap   = heap  << SyntaxQuote << token     << []
            state  = state << :close_one  << :expr_one
          when "'"
            heap   = heap  << Quote       << token     << []
            state  = state << :close_one  << :expr_one
          when "~"
            heap   = heap  << Unquote     << token     << []
            state  = state << :close_one  << :expr_one
          when "^"
            heap   = heap  << MetaData    << token     << []
            state  = state << :close_one  << :expr_one
          when ';'
            state <<= :comment
          when '#'
            state <<= :sharp
          when ':'
            state = state << :keyword
            heap  = heap  << token    << ""
          when '"'
            state = state << :string
            heap  = heap  << token   << ""
          when '(', '[', '{'
            heap  = heap  << OPEN_MAP[c] << token << []
            state = state << :expr
          when ')', ']', '}'
            state = state.pop # expr
            els  = heap.last; heap = heap.pop
            tok  = heap.last; heap = heap.pop
            type = heap.last; heap = heap.pop

            ex = CLOS_REV_MAP[type]
            unless c === ex
              ser!("Wrong closing delimiter. Expected '#{ex}' got '#{c}'")
            end
            heap.last << type.new(tok.extend!(@pos), els)
          when SYM_START_REGEXP
            state = state << :symbol
            heap  = heap  << token   << ""
            redo
          when NUMBER_RE
            state = state << :number
            heap  = heap  << token   << ""
            redo
          else
            ser!("Unexpected char: #{c}")
          end
        when :close_one
          inner = heap.last; heap = heap.pop
          tok   = heap.last; heap = heap.pop
          type  = heap.last; heap = heap.pop

          raise "Internal error" if inner.length != 1
          heap.last << type.new(tok.extend!(@pos), inner[0])
          state = state.pop
          redo
        when :comment
          state = state.pop if c == "\n"
        when :sharp
          state = state.pop
          case c
          when '('
            heap  = heap  << Closure    << token << [] << List << token << []
            state = state << :close_one << :expr
          when '{'
            heap  = heap  << Set        << token << []
            state = state << :expr
          when '"'
            heap  = heap  << token      << ""
            state = state << :regexp
          else
            ser!("Unexpected char after #: #{c}")
          end
        when :string, :regexp
          case c
          when '"'
            value = heap.last; heap = heap.pop
            tok   = heap.last; heap = heap.pop
            case state.last
            when :string
              heap.last << String.new(tok.extend!(@pos), value)
            when :regexp
              heap.last << RegExp.new(tok.extend!(@pos), value)
            else
              raise "Internal error"
            end
            state = state.pop
          else
            heap.last << c
          end
        when :number
          case c
          when NUMBER_RE
            heap.last << c
          else
            value = heap.last; heap = heap.pop
            tok   = heap.last; heap = heap.pop
            heap.last << Number.new(tok.extend!(@pos), value.to_f)
            state = state.pop
            redo
          end
        when :symbol
          case c
          when SYM_INNER_REGEXP
            heap.last << c
          else
            value = heap.last; heap = heap.pop
            tok   = heap.last; heap = heap.pop
            heap.last << Symbol.new(tok.extend!(@pos), value)
            state = state.pop
            redo
          end
        when :keyword
          case c
          when SYM_INNER_REGEXP
            heap.last << c
          else
            value = heap.last; heap = heap.pop
            tok   = heap.last; heap = heap.pop
            heap.last << Keyword.new(tok.extend!(@pos), value)
            state = state.pop
            redo
          end
        else
          raise "Inconsistent state: #{state.last}"
        end # case state
        @pos += 1
      end # each_char

      case state.last
      when :number
        value = heap.last; heap = heap.pop
        tok   = heap.last; heap = heap.pop
        heap.last << Number.new(tok.extend!(@pos), value.to_f)
      when :keyword
        value = heap.last; heap = heap.pop
        tok   = heap.last; heap = heap.pop
        heap.last << Keyword.new(tok.extend!(@pos), value)
      when :symbol
        value = heap.last; heap = heap.pop
        tok   = heap.last; heap = heap.pop
        heap.last << Symbol.new(tok.extend!(@pos), value)
      end

      if heap.length > 1
        until heap.empty?
          type = heap.last; heap = heap.pop
          if Class === type
            ser!("Unclosed #{type.name.split('::').last}")
            break
          end
        end
      end

      nodes.map! do |node|
        post_parse(node)
      end

      return nodes
    end

    def token
      Token.new(file, @pos)
    end

    def file
      @options[:file] || "<stdin>"
    end

    def ser!(msg, token = nil)
      start = token ? token.start : @pos
      length = token ? token.length : 1

      line, column = line_column(@input, start)
      snippet = snippet(@input, start, length)

      raise Shin::SyntaxError, "#{msg} at #{file}:#{line}:#{column}\n\n#{snippet}\n\n"
    end

    # Post-parsing logic (auto-gensym, etc.)

    def post_parse(node, trail = [])
      case node
      when Sequence
        node = node.clone
        _trail = trail + [node]
        node.inner.map! do |child|
          post_parse(child, _trail)
        end
        node
      when SyntaxQuote
        node = node.clone
        candidate = LetCandidate.new(node)

        _trail = trail + [node, candidate]
        inner = post_parse(node.inner, _trail)

        if candidate.useful?
          candidate.let
        else
          SyntaxQuote.new(node.token, inner)
        end
      when Symbol
        if node.value.end_with? '#'
          t = node.token
          candidate = nil
          quote = nil
          found = false
          trail.reverse_each do |parent|
            if SyntaxQuote === parent
              found = true
              quote = parent
              break
            end
            candidate = parent
          end

          unless found
            raise "auto-gensym used outside syntax quote: #{node}"
          end

          name = node.value[0..-2]
          sym = candidate.lazy_make(name)
          return Unquote.new(t, Symbol.new(t, sym))
        end
        node
      else
        node
      end
    end
  end

  class LetCandidate
    include Shin::AST

    attr_reader :t
    attr_reader :let

    def initialize(node)
      @t = node.token
      @let = List.new(t)
      @let.inner << Symbol.new(t, "let")
      @decls = Vector.new(t)
      @let.inner << @decls
      @let.inner << node
      @cache = {}
    end

    def lazy_make(name)
      sym = @cache[name]
      unless sym
        sym = "#{name}#{Shin::Mutator.fresh_sym}"
        @cache[name] = sym
        @decls.inner << Symbol.new(t, sym)
        @decls.inner << List.new(t, [Symbol.new(t, "gensym"), String.new(t, name)])
      end
      sym
    end

    def to_s
      "LetCandidate(#{@let}, cache = #{@cache})"
    end

    def useful?
      !@decls.inner.empty?
    end

  end
end
