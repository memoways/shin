
require 'shin/utils'

module Shin
  class NsParser
    include Shin::Utils::Matcher

    attr_reader :mod
    @@seed = 0

    def initialize(mod)
      @mod = mod
    end

    def parse
      return if mod.ns

      nsdef = mod.ast[0]
      if nsdef && nsdef.list?
        matches?(nsdef.inner, "ns :sym :expr*") do |_, name, specs|
          # get rid of nsdef (don't translate it)
          # FIXME: it's probably not good for NsParser to mutate the AST.
          # Maybe translator could be a champ and just ignore it?
          mod.ast = mod.ast.drop(1)

          mod.ns = name.value
          specs.each { |spec| translate_spec(spec) }
        end
      end

      mod.ns ||= "anonymous#{fresh}"
      mod.requires << core_require if mod.ns != 'shin.core'

      puts "Requires for #{mod.ns}:\n#{mod.requires.join("\n")}"
    end

    def translate_spec(spec)
      list = spec.inner
      type = list.first.value rescue nil
      raise "invalid spec" unless type
      raise "invalid spec type #{type}: expected 'use' or 'require'" unless ['use', 'require'].include? type

      list.drop(1).each do |libspec|
        els = case libspec
        when Shin::AST::Sequence
          libspec.inner
        when Shin::AST::Symbol
          [libspec]
        else
          raise "invalid libspec: #{libspec}"
        end

        raise "invalid libspec: shouldn't be empty #{els}" if els.empty?
        raise "expected sym" unless els.first.sym?
        req = Require.new(els.first.value)
        mod.requires << req
        req.refer = :all if 'use' === type
        els = els.drop(1)

        until els.empty?
          raise "invalid directives in: #{els}" unless els.length.even?

          directive, args = els
          raise "invalid directive: #{directive}" unless directive.kw?
          els = els.drop(2)

          case directive.value
          when 'as'
            raise ":as needs a symbol as arg, not #{args}" unless args.sym?
            req.as = args.value
          when 'refer'
            raise ":refer invalid outside of :require" unless type === 'require'

            case
            when Shin::AST::Sequence === args
              args.inner.each do |arg|
                raise "can only refer symbols: #{arg}" unless arg.sym?
                req.refer << arg.value
              end
            when args.kw?('all')
              req.refer = :all
            else
              raise "invalid refer-arg: #{args}"
            end
          when 'only'
            raise ":only invalid outside of :require" unless type === 'use'

            raise ":only needs a sequence as arg, not #{args}" unless Shin::AST::Sequence === args
            res.refer = []
            args.inner.each do |arg|
              raise "can only refer symbols: #{arg}" unless arg.sym?
              req.refer << arg.value
            end
          end
        end 
      end
    end

    def core_require
      req = Require.new('shin.core')
      req.refer = :all
      req.as = 'shin'
      req
    end

    def fresh
      @@seed += 1
    end

  end

  class Require
    attr_accessor :ns
    attr_accessor :refer
    attr_accessor :as
    attr_accessor :js

    def initialize(ns, refer: [], as: nil)
      @js = false
      if ns.start_with? 'js/'
        # strip leading 'js/'
        ns = ns[3..-1]
        @js = true
      end

      @ns = ns
      @as = as || ns
      @refer = refer
    end

    def all?
      @refer === :all
    end

    def js?
      @js
    end

    def to_s
      "(:require [#{js ? 'js/' : ''}#{ns} :refer #{refer.inspect} :as #{as}])"
    end
  end
end

