
require 'shin/utils/mangler'
require 'set'

module Shin
  module Utils
    module Mimic
      DEBUG = ENV['MIMIC_DEBUG']

      module ClassMethod
        include Shin::Utils::Mangler

        attr_reader :protocols

        def core_proto_name(proto)
          "cljs$dcore$v#{proto}"
        end

        def implement(proto, &block)
          @protocols ||= Set.new
          @protocols << core_proto_name(proto)

          if proto == :IFn
            # IFn is special, cf. #50
            define_method(:call) do |*args|
              sym = method_sym('-invoke', args.length)
              send(sym, *args)
            end
          end

          block.call if block
        end

        def method_sym(name, arity)
          mangle("#{name}$arity#{arity}")
        end

        def defn(name, &block)
          sym = self.method_sym(name, block.arity)
          define_method(sym, &block)
        end
      end

      def self.included(base)
        base.extend(ClassMethod)
      end

      def [](x)
        return true if self.class.protocols.include?(x)
        puts "[#{self.class.name}] does not implement Clojure protocol #{x}" if DEBUG
        nil
      end

      def method_sym(name, arity)
        self.class.method_sym(name, arity)
      end

      def core_proto_name(name)
        self.class.core_proto_name(name)
      end

      def invoke(name, *args)
        send(method_sym(name, args.length + 1), *([self].concat(args)))
      end

      def js_invoke(val, name, *args)
        name = method_sym(name, args.length + 1)
        f = val[name]
        if f
          f.methodcall(val, val, *args)
        else
          raise "Can't invoke #{name} on JS object #{val}"
        end
      end

      # AST nodes -> ClojureScript data structures
      def unwrap(node)
        case node
        when Shin::AST::Literal
          node.value
        when Shin::AST::Sequence, Shin::AST::Keyword, Shin::AST::Symbol
          node
        else
          raise "Not sure how to unwrap: #{node.inspect}"
        end
      end

      # ClojureScript data structures -> AST nodes
      def wrap(val)
        case val
        when Shin::AST::Node
          node
        when Fixnum, Float, String
          # using our token.. better than muffin!
          Shin::AST::Literal.new(token, val)
        when V8::Object
          type = v8_type(val)
          case type
          when :keyword
            name = js_invoke(val, "-name")
            Shin::AST::Keyword.new(Token.dummy, name)
          when :symbol
            name = js_invoke(val, "-name")
            Shin::AST::Symbol.new(Token.dummy, name)
          else
            raise "Unknown V8 type: #{type}"
          end
        else
          raise "Not sure how to wrap: #{val} of type #{val.class.name}"
        end
      end

      def v8_type(val)
        case true
        when val[core_proto_name("IKeyword")]
          :keyword
        when val[core_proto_name("ISymbol")]
          :symbol
        when val[core_proto_name("IList")]
          :list
        when val[core_proto_name("IVector")]
          :vector
        when val[core_proto_name("IMap")]
          :map
        when val[core_proto_name("IUnquote")]
          :unquote
        else
          :unknown
        end
      end

      def pr_str(val)
        _pr_str = method_sym("-pr-str", 1)
        if val.respond_to?(_pr_str)
          val.send(_pr_str, val)
        else
          val.to_s
        end
      end
    end
  end
end
