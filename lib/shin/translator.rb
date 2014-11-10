
require 'shin/jst'
require 'shin/ast'
require 'shin/utils'

module Shin
  # Converts Shin AST to JST
  class Translator
    include Shin::LineColumn
    include Shin::Snippet

    def initialize(p_input, options)
      @input = p_input.dup
      @options = options
    end

    def translate(ast)
      program = Shin::JST::Program.new
      ast.each do |node|
        case
        when node.list?
          first = node.inner.first
          case
          when first.identifier?("defn")
            program.body << translate_defn(node.inner[1..-1])
          else
            puts "Unknown node: #{first.inspect}"
          end
        else
        end
      end

      program
    end

    protected

    def translate_defn(list)
      unless list.first.identifier?
        ser!("Expected function name", list.first.token)
      end

      id = list.first
      decl = Shin::JST::FunctionDeclaration.new(make_ident(id.value))
      list = list[1..-1]

      unless list.first.vector?
        ser!("Expected argument vector after function name", id.token)
      end
      list.first.inner.each do |arg|
        unless arg.identifier?
          ser!("Expected identifier in function arg list", arg.token)
        end
        decl.params << make_ident(arg.value)
      end
      list = list[1..-1]

      decl.body = block = Shin::JST::BlockStatement.new()
      inner_count = list.count
      list.each_with_index do |expr, i|
        last = (inner_count - 1 == i)

        node = translate_expr(expr)
        node = if last
          make_rstat(node)
        else
          make_estat(node)
        end

        block.body << node
      end

      decl
    end

    def translate_expr(expr)
      case
      when expr.identifier?
        return make_ident(expr.value)
      when expr.list?
        list = expr.inner
        first = list.first
        case
        when first.instance_of?(Shin::AST::MethodCall)
          property = translate_expr(list[0].id)
          object = translate_expr(list[1])
          mexp = Shin::JST::MemberExpression.new(object, property, false)
          call = Shin::JST::CallExpression.new(mexp)
          list[2..-1].each do |arg|
            call.arguments << translate_expr(arg)
          end
          return call
        when first.identifier?
          # function call
          call = Shin::JST::CallExpression.new(make_ident(first.value))
          list[1..-1].each do |arg|
            call.arguments << translate_expr(arg)
          end
          return call
        else
          ser!("Unknown list expr form", expr.token)
        end
      when expr.instance_of?(Shin::AST::String)
        Shin::JST::Literal.new(expr.value)
      else
        ser!("Unknown expr form", expr.token)
        nil
      end
    end

    def make_ident(id)
      Shin::JST::Identifier.new(id)
    end

    def make_rstat(node)
      Shin::JST::ReturnStatement.new(node)
    end

    def make_estat(node)
      Shin::JST::ExpressionStatement.new(node)
    end

    def file
      @options[:file] || "<stdin>"
    end


    def ser!(msg, token)
      start = token.start
      length = token.length

      line, column = line_column(@input, start)
      snippet = snippet(@input, start, length)

      raise "#{msg} at #{file}:#{line}:#{column}\n\n#{snippet}\n\n"
    end
  end
end
