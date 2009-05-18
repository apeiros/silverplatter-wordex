#--
# Copyright 2009 by Stefan Rusterholz.
# All rights reserved.
# See LICENSE.txt for permissions.
#++



require 'forwardable'



module SilverPlatter
  class WordEx
    include Comparable

    module Pattern
      # Multiple items of a specific regex
      def self.one_or_more_of(single)
        "(?:#{single}(?:(?:,\\s*|\\s+)#{single})*?)"
      end

      def self.one_of(items)
        "(?i:#{items.map { |item| Regexp.escape(item) }.join('|')})"
      end

      def self.quoted_variants(pattern)
        "(?:#{pattern}|\"#{pattern}\"|'#{pattern}')"
      end

      # A single argument
      Argument  = '(?:(?:\\\\.|[^\\\\"\'\s])+|"(?:\\\\.|[^\\\\"])*"|\'(?:\\\\.|[^\\\\\'])*\')'.freeze

      # A list of arguments, comma or whitespace separated
      Arguments = one_or_more_of(Argument).freeze

      # An arbitrary string
      String    = "(?:.*?)".freeze

      # In the definition string, a variable definition
      Variable  = /([+:*])?(\w+)(?:<([^>]+)>)?(?:@([\w+-]+))?(?:\{([\w,]+)\})?|(\S+)/
    end

    class MatchData
      extend Forwardable

      def_delegators :@matchdata,
                       :captures,
                       :begin,
                       :captures,
                       :end,
                       :length,
                       :match,
                       :offset,
                       :post_match,
                       :pre_match,
                       :pretty_print,
                       :select,
                       :size,
                       :string,
                       :to_a,
                       :to_s

      def initialize(matchdata, captures)
        @params    = {}
        @captures  = []
        @matchdata = matchdata
        captures.zip(matchdata.captures) do |capture, value|
          if value then
            if capture.scan then
              processed = value.scan(capture.scan).map { |element|
                if capture.typemap then
                  capture.typemap.map(self, unwrap(element))
                else
                  unwrap(element)
                end
              }
            else
              processed = capture.typemap ? capture.typemap.map(self, unwrap(value)) : unwrap(value)
            end
            @params[capture.name] = processed
            @captures            << processed
          else
            @params[capture.name] = nil
            @captures            << nil
          end
        end
      end
      
      def [](*key)
        return @captures[*key] if key.size > 1
        @params[*key] || @matchdata[*key]
      end

      def values_at(*keys)
        keys.map { |key| self[key] }
      end

    private
      # remove quotes if necessary and unescape
      def unwrap(value)
        value = case value[0,1]
          when '"': value[1..-2].gsub(/\\./) { |m| ['"', "'", ' '].include?(m) ? m[1,1] : m }
          when "'": value[1..-2].gsub(/\\./) { |m| ['"', "'", ' '].include?(m) ? m[1,1] : m }
          else      value.gsub(/\\./) { |m| ['"', "'", ' '].include?(m) ? m[1,1] : m }
        end
      end
    end

    Capture = Struct.new("Capture", :name, :scan, :typemap)

    attr_reader :hash
    attr_reader :regexp

    def initialize(expression)
      @expression    = expression
      @captures      = []
      @hash          = @name.hash

      # process expression
      structure      = structure(expression)

      append         = "^"
      captures       = []
      structure.each { |item|
        if Array === item
          optional(item, append)
        else
          regexify(item, append)
        end
      }
      append << "\s*$"

      # HAX, ported from butler, clean up later
      append.sub!(/^\^\\s\+/, '^')

      @regexp        = Regexp.new(append)
    end

    def match(string)
      return nil unless match = @regexp.match(string)
      MatchData.new(match, @captures)
    rescue ValidationFailure
      nil
    rescue Exception => e
      raise
    end

    def eql?(other)
      other.kind_of?(self.class) && @expression.eql?(other.expression)
    end

    def inspect
      "#<%s:0x%08x %s %s>" %  [
        self.class,
        object_id << 1,
        @expression.inspect,
        @regexp.inspect
      ]
    end

    def to_s
      "#<%s:0x%08x %s>" %  [
        self.class,
        object_id << 1,
        @expression.inspect
      ]
    end

    private
    # parse the optional parts of a mapping and structure it as nested array
    def structure(str)
      curr   = []
      stack  = [curr]
      offset = 0
      o,c = str.index("[", offset), str.index("]", offset)

      while o or c
        if o && c && o < c then
          substr = str[offset...o].strip
          curr  << substr unless substr.empty?
          curr  << []
          stack << curr.last
          curr   = stack.last
          offset = o+1
        elsif c then
          substr = str[offset...c].strip
          curr << substr unless substr.empty?
          stack.pop
          curr = stack.last
          offset = c+1
        else
          raise "Invalid expression, Orphan ["
        end
        o,c = str.index("[", offset), str.index("]", offset)
      end
      curr << str[offset..-1].strip unless offset == str.length
      curr
    end # structure

    # recursively create the regex for structured optional parts
    def optional(item, append)
      append << "(?:"
      item.each { |item|
        if Array === item then
          optional(item, append)
        else
          regexify(item, append)
        end
      }
      append << ")??"
    end

    # convert a part into its regex pendant, parse out captures, types and restrictions
    def regexify(string, append)
      string.scan(Pattern::Variable) { |type, name, usage, map, one_of, literal|
        if literal then
          # non-whitespace, non-word, non-argument(s) - probably interpunctuation
          append << Regexp.escape(literal)
        else
          case type
            when nil
              raise "Forgot :, * or + prefix? Invalid pattern" if map or one_of
              # literal
              append << '\s+'+name
            when "+"
              # string
              append   << "\\s+(#{Pattern::String})"
              @captures << Capture.new(name.to_sym, nil, nil)
            when ":"
              # argument
              raise "Unknown type '#{map}'" if map and !(typemap = MappingTypes[map])
              if one_of then
                append   << "\\s+(#{Pattern.one_of(one_of.split(/,\s*/))})"
              elsif map then
                append   << "\\s+(#{typemap.regex})"
              else
                append   << "\\s+(#{Pattern::Argument})"
              end
              @captures << Capture.new(name.to_sym, nil, MappingTypes[map])
            when "*"
              # arguments
              raise "Unknown type '#{map}'" if map and !(typemap = MappingTypes[map])
              if one_of then
                scan = Pattern.one_of(one_of.split(/,\s*/))
                append   << "\\s+(#{Pattern.one_or_more_of(scan)})"
                scan = /#{scan}/
              elsif map then
                append   << "\\s+(#{Pattern.one_or_more_of(typemap.regex)})"
                scan = typemap.regex
              else
                append   << "\\s+(#{Pattern.one_or_more_of(Pattern::Argument)})"
                scan = /#{Pattern::Argument}/
              end
              @captures << Capture.new(name.to_sym, /#{scan}/, typemap)
          end
        end
      }
    end



    # For TypeMaps, to indicate that a validation failed
    class ValidationFailure < RuntimeError; end


    # Map arguments of a specific type to their actual value
    # The mapping may raise an exception inherited from
    # WordEx::ValidationFailure to indicate that the value
    # didn't validate
    class TypeMap

      # name of the typemap
      attr_reader :name

      # type matches only this regex
      attr_reader :regex

      # validate and convert the matched value
      attr_reader :validation

      # Example:
      #   TypeMap.new "IP", /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/ do |wordex, value|
      #     value.split(/\./).map { |e|
      #       i = e.to_i
      #       raise ValidationFailure unless i.between?(0,255)
      #       i
      #     }
      #   end
      def initialize(name, regex, &validation)
        @name       = name
        @regex      = regex
        @validation = validation
      end

      # map the value, can raise a ValidationFailure
      def map(wordex, value)
        @validation ? @validation[wordex, value] : value
      end
    end



    # add a mapping type for :map:'s
    # The regular expression MUST NOT contain any captures!
    # For grouping use (?: ... ), which does not capture
    # The provided block can convert the value and do additional testing for validity
    # If the value is invalid, raise a ValidationFailure
    # Example:
    #   map_type "IP", /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/ do |wordex, value|
    #     value.split(/\./).map { |e|
    #       i = e.to_i
    #       raise ValidationFailure unless i.between?(0,255)
    #       i
    #     }
    #   end
    def self.map_type(name, regex, &validation)
      @mapping_type[name] = TypeMap.new(name, regex, &validation)
    end

    # get the TypeMap for a type
    def self.typemap(name)
      (@mapping_type || MappingTypes)[name]
    end

    # Basic mapping types, includes:
    # * Integer:     any valid integer. Converted to a Fix- or Bignum.
    # * +Integer:    any positive integer. Converted to a Fix- or Bignum.
    # * -Integer:    any negative integer. Converted to a Fix- or Bignum.
    # * Float:       any valid float. Converted to a Float.
    # * +Float:      any positive float. Converted to a Float.
    # * -Float:      any negative float. Converted to a Float.
    MappingTypes = {}
    # Provide additional warnings
    def MappingTypes.[]=(name, typemap) # :nodoc:
      warn "redefining TypeMap '#{name}'" if has_key?(name)
      super
    end
    [
    	# name, regex, validation
      ["Integer",     %r{[+-]?\d+},            proc { |wordex, value| Integer(value) }],
      ["+Integer",    %r{\+?\d+},              proc { |wordex, value| Integer(value) }],
      ["-Integer",    %r{\-\d+},               proc { |wordex, value| Integer(value) }],
      ["Float",       %r{[+-]?\d+(?:\.\d+)?},  proc { |wordex, value| Float(value) }],
      ["+Float",      %r{\+?\d+(?:\.\d+)?},    proc { |wordex, value| Float(value) }],
      ["-Float",      %r{\-?\d+(?:\.\d+)?},    proc { |wordex, value| Float(value) }],
    ].each { |name, regex, validation|
      MappingTypes[name] = TypeMap.new(
        name,
        Pattern.quoted_variants(regex),
        &validation
      )
    }
  end
end
