class FFIGen
  RUBY_KEYWORDS = %w{alias allocate and begin break case class def defined do else elsif end ensure false for if in initialize module next nil not or redo rescue retry return self super then true undef unless until when while yield}
  
  require "ffi_gen/clang"
  
  class << Clang
    def get_children(declaration)
      children = []
      visit_children declaration, lambda { |child, child_parent, child_client_data|
        children << child
        :continue
      }, nil
      children
    end
    
    def get_spelling_location_data(location)
      file_ptr = FFI::MemoryPointer.new :pointer
      line_ptr = FFI::MemoryPointer.new :uint
      column_ptr = FFI::MemoryPointer.new :uint
      offset_ptr = FFI::MemoryPointer.new :uint
      get_spelling_location location, file_ptr, line_ptr, column_ptr, offset_ptr
      { file: file_ptr.read_pointer, line: line_ptr.read_uint, column: column_ptr.read_uint, offset: offset_ptr.read_uint }
    end
  end
  
  class Clang::String
    def to_s
      Clang.get_c_string self
    end
    
    def to_s_and_dispose
      str = to_s
      Clang.dispose_string self
      str
    end
  end
  
  class Clang::Cursor
    def ==(other)
      other.is_a?(Clang::Cursor) && Clang.equal_cursors(self, other) == 1
    end
    
    def eql?(other)
      self == other
    end
    
    def hash
      Clang.hash_cursor self
    end
  end
  
  class Clang::Type
    def ==(other)
      other.is_a?(Clang::Type) && Clang.equal_types(self, other) == 1
    end
    
    def eql?(other)
      self == other
    end
    
    def hash
      0 # no hash available
    end
  end
  
  class Enum
    attr_accessor :name
    attr_reader :constants, :comment
    
    def initialize(generator, name, comment)
      @generator = generator
      @name = name
      @comment = comment
      @constants = []
    end
    
    def write(writer)
      prefix_length = 0
      suffix_length = 0
      
      unless @constants.size < 2
        search_pattern = @constants.all? { |constant| constant[:name].include? "_" } ? /(?<=_)/ : /[A-Z]/
        first_name = @constants.first[:name]
        
        loop do
          position = first_name.index(search_pattern, prefix_length + 1) or break
          prefix = first_name[0...position]
          break if not @constants.all? { |constant| constant[:name].start_with? prefix }
          prefix_length = position
        end
        
        loop do
          position = first_name.rindex(search_pattern, first_name.size - suffix_length - 1) or break
          prefix = first_name[position..-1]
          break if not @constants.all? { |constant| constant[:name].end_with? prefix }
          suffix_length = first_name.size - position
        end
      end
      
      @constants.each do |constant|
        constant[:symbol] = ":#{@generator.to_ruby_lowercase constant[:name][prefix_length..(-1 - suffix_length)]}"
      end
      
      writer.comment do
        writer.write_description @comment
        writer.puts "", "<em>This entry is only for documentation and no real method. The FFI::Enum can be accessed via #enum_type(:#{ruby_name}).</em>"
        writer.puts "", "=== Options:"
        @constants.each do |constant|
          writer.puts "#{constant[:symbol]} ::"
          writer.write_description constant[:comment], false, "  ", "  "
        end
        writer.puts "", "@method _enum_#{ruby_name}_", "@return [Symbol]", "@scope class"
      end
      
      writer.puts "enum :#{ruby_name}, ["
      writer.indent do
        writer.write_array @constants, "," do |constant|
          "#{constant[:symbol]}#{constant[:value] ? ", #{constant[:value]}" : ''}"
        end
      end
      writer.puts "]", ""
    end
    
    def ruby_name
      @ruby_name ||= @generator.to_ruby_lowercase @name
    end
  end
  
  class StructOrUnion
    attr_accessor :name, :comment
    attr_reader :fields, :written
    
    def initialize(generator, name, is_union)
      @generator = generator
      @name = name
      @is_union = is_union
      @comment = ""
      @fields = []
      @written = false
    end
    
    def write(writer)
      @fields.each do |field|
        field[:symbol] = ":#{@generator.to_ruby_lowercase field[:name]}"
        field[:type_data] = @generator.map_type field[:type]
      end
      
      writer.comment do
        writer.write_description @comment
        unless @fields.empty?
          writer.puts "", "= Fields:"
          @fields.each do |field|
            writer.puts "#{field[:symbol]} ::"
            writer.write_description field[:comment], false, "  (#{field[:type_data][:description]}) ", "  "
          end
        end
      end
      
      @fields << { symbol: ":dummy", type_data: { ffi_type: ":char" } } if @fields.empty?
      
      writer.puts "class #{ruby_name} < #{@is_union ? 'FFI::Union' : 'FFI::Struct'}"
      writer.indent do
        writer.write_array @fields, ",", "layout ", "       " do |field|
          "#{field[:symbol]}, #{field[:type_data][:ffi_type]}"
        end
      end
      writer.puts "end", ""
      
      @written = true
    end
    
    def ruby_name
      @ruby_name ||= @generator.to_ruby_camelcase @name
    end
  end
  
  class FunctionOrCallback
    attr_reader :name, :parameters, :comment
    attr_accessor :return_type
    
    def initialize(generator, name, is_callback, blocking, comment)
      @generator = generator
      @name = name
      @parameters = []
      @is_callback = is_callback
      @blocking = blocking
      @comment = comment
    end
    
    def write(writer)
      @parameters.each do |parameter|
        parameter[:type_data] = @generator.map_type parameter[:type]
        parameter[:ruby_name] = !parameter[:name].empty? ? @generator.to_ruby_lowercase(parameter[:name]) : parameter[:type_data][:parameter_name]
        parameter[:description] = []
      end
      return_type_data = @generator.map_type @return_type
      
      function_description = []
      return_value_description = []
      current_description = function_description
      @comment.split("\n").map do |line|
        line = writer.prepare_comment_line line
        if line.gsub! /\\param (.*?) /, ''
          parameter = @parameters.find { |parameter| parameter[:name] == $1 }
          if parameter
            current_description = parameter[:description]
          else
            current_description << "#{$1}: "
          end
        end
        current_description = return_value_description if line.gsub! '\\returns ', ''
        current_description << line
      end
      
      writer.puts "@blocking = true" if @blocking
      writer.comment do
        writer.write_description function_description
        writer.puts "", "<em>This entry is only for documentation and no real method.</em>" if @is_callback
        writer.puts "", "@method #{@is_callback ? "_callback_#{ruby_name}_" : ruby_name}(#{@parameters.map{ |parameter| parameter[:ruby_name] }.join(', ')})"
        @parameters.each do |parameter|
          writer.write_description parameter[:description], false, "@param [#{parameter[:type_data][:description]}] #{parameter[:ruby_name]} ", "  "
        end
        writer.write_description return_value_description, false, "@return [#{return_type_data[:description]}] ", "  "
        writer.puts "@scope class"
      end
      
      ffi_signature = "[#{@parameters.map{ |parameter| parameter[:type_data][:ffi_type] }.join(', ')}], #{return_type_data[:ffi_type]}"
      if @is_callback
        writer.puts "callback :#{ruby_name}, #{ffi_signature}", ""
      else
        writer.puts "attach_function :#{ruby_name}, :#{@name}, #{ffi_signature}", ""
      end
    end
    
    def ruby_name
      @ruby_name ||= @generator.to_ruby_lowercase @name, true
    end
  end
  
  class Constant
    def initialize(generator, name, value)
      @generator = generator
      @name = name
      @value = value
    end
    
    def write(writer)
      writer.puts "#{@generator.to_ruby_lowercase(@name, true).upcase} = #{@value}", ""
    end
  end
  
  class Writer
    attr_reader :output
    
    def initialize
      @indentation = ""
      @output = ""
    end
    
    def indent(prefix = "  ")
      previous_indentation = @indentation
      @indentation += prefix
      yield
      @indentation = previous_indentation
    end
    
    def comment(&block)
      indent "# ", &block
    end
    
    def puts(*lines)
      lines.each do |line|
        @output << "#{@indentation}#{line}\n"
      end
    end
    
    def write_array(array, separator = "", first_line_prefix = "", other_lines_prefix = "")
      array.each_with_index do |entry, index|
        entry = yield entry if block_given?
        puts "#{index == 0 ? first_line_prefix : other_lines_prefix}#{entry}#{index < array.size - 1 ? separator : ''}"
      end
    end
    
    def prepare_comment_line(line)
      line = line.dup
      line.sub! /\ ?\*+\/\s*$/, ''
      line.sub! /^\s*\/?\*+ ?/, ''
      line.gsub! /\\(brief|determine) /, ''
      line.gsub! '[', '('
      line.gsub! ']', ')'
      line
    end
    
    def write_description(description, not_documented_message = true, first_line_prefix = "", other_lines_prefix = "")
      if description.is_a? String
        description = description.split("\n").map { |line| prepare_comment_line(line) }
      end
      
      description.shift while not description.empty? and description.first.strip.empty?
      description.pop while not description.empty? and description.last.strip.empty?
      description << (not_documented_message ? "(Not documented)" : "") if description.empty?
      
      write_array description, "", first_line_prefix, other_lines_prefix
    end
  end
  
  attr_reader :ruby_module, :ffi_lib, :headers, :output, :blacklist, :cflags

  def initialize(options = {})
    @ruby_module   = options[:ruby_module] or fail "No module name given."
    @ffi_lib       = options[:ffi_lib] or fail "No FFI library given."
    @headers       = options[:headers] or fail "No headers given."
    @cflags        = options.fetch :cflags, []
    @prefixes      = options.fetch :prefixes, []
    @blacklist     = options.fetch :blacklist, []
    @blocking      = options.fetch :blocking, []
    @ffi_lib_flags = options.fetch :ffi_lib_flags, nil
    @output        = options.fetch :output, $stdout
    
    blacklist = @blacklist
    @blacklist = lambda { |name| blacklist.include? name } if @blacklist.is_a? Array
    
    @translation_unit = nil
    @declarations = nil
  end
  
  def generate
    writer = Writer.new
    writer.puts "# Generated by ffi_gen. Please do not change this file by hand.", "", "require 'ffi'", "", "module #{@ruby_module}"
    writer.indent do
      writer.puts "extend FFI::Library"
      writer.puts "ffi_lib_flags #{@ffi_lib_flags.map(&:inspect).join(', ')}" if @ffi_lib_flags
      writer.puts "ffi_lib #{@ffi_lib.inspect}", ""
      declarations.values.compact.uniq.each do |declaration|
        declaration.write writer
      end
    end
    writer.puts "end"
    if @output.is_a? String
      File.open(@output, "w") { |file| file.write writer.output }
      puts "ffi_gen: #{@output}"
    else
      @output.write writer.output
    end
  end
  
  def translation_unit
    return @translation_unit unless @translation_unit.nil?
    
    args = []
    @headers.each do |header|
      args.push "-include", header unless header.is_a? Regexp
    end
    args.concat @cflags
    args_ptr = FFI::MemoryPointer.new :pointer, args.size
    pointers = args.map { |arg| FFI::MemoryPointer.from_string arg }
    args_ptr.write_array_of_pointer pointers
    
    index = Clang.create_index 0, 0
    @translation_unit = Clang.parse_translation_unit index, File.join(File.dirname(__FILE__), "ffi_gen/empty.h"), args_ptr, args.size, nil, 0, Clang.enum_type(:translation_unit_flags)[:detailed_preprocessing_record]
    
    Clang.get_num_diagnostics(@translation_unit).times do |i|
      diag = Clang.get_diagnostic @translation_unit, i
      $stderr.puts Clang.format_diagnostic(diag, Clang.default_diagnostic_display_options).to_s_and_dispose
    end
    
    @translation_unit
  end
  
  def declarations
    return @declarations unless @declarations.nil?
    
    header_files = []
    Clang.get_inclusions translation_unit, proc { |included_file, inclusion_stack, include_length, client_data|
      filename = Clang.get_file_name(included_file).to_s_and_dispose
      header_files << included_file if @headers.any? { |header| header.is_a?(Regexp) ? header =~ filename : filename.end_with?(header) }
    }, nil
    
    @declarations = {}
    unit_cursor = Clang.get_translation_unit_cursor translation_unit
    previous_declaration_end = Clang.get_cursor_location unit_cursor
    Clang.get_children(unit_cursor).each do |declaration|
      file = Clang.get_spelling_location_data(Clang.get_cursor_location(declaration))[:file]
      
      extent = Clang.get_cursor_extent declaration
      comment_range = Clang.get_range previous_declaration_end, Clang.get_range_start(extent)
      unless [:enum_decl, :struct_decl, :union_decl].include? declaration[:kind] # keep comment for typedef_decl
        previous_declaration_end = Clang.get_range_end extent
      end 
      
      next if not header_files.include? file
      
      name = Clang.get_cursor_spelling(declaration).to_s_and_dispose
      name = nil if name.empty?
      next if @blacklist[name]
      
      comment = extract_comment translation_unit, comment_range
      
      read_named_declaration declaration, comment
    end

    @declarations
  end
  
  def read_named_declaration(declaration, comment)
    name = Clang.get_cursor_spelling(declaration).to_s_and_dispose
    name = nil if name.empty?

    case declaration[:kind]
    when :enum_decl
      enum = Enum.new self, name, comment
      @declarations[Clang.get_cursor_type(declaration)] = enum
      
      previous_constant_location = Clang.get_cursor_location declaration
      Clang.get_children(declaration).each do |enum_constant|
        constant_name = Clang.get_cursor_spelling(enum_constant).to_s_and_dispose
        
        constant_value = nil
        value_cursor = Clang.get_children(enum_constant).first
        constant_value = value_cursor && case value_cursor[:kind]
        when :integer_literal
          tokens_ptr_ptr = FFI::MemoryPointer.new :pointer
          num_tokens_ptr = FFI::MemoryPointer.new :uint
          Clang.tokenize translation_unit, Clang.get_cursor_extent(value_cursor), tokens_ptr_ptr, num_tokens_ptr
          token = Clang::Token.new tokens_ptr_ptr.read_pointer
          literal = Clang.get_token_spelling(translation_unit, token).to_s_and_dispose
          Clang.dispose_tokens translation_unit, tokens_ptr_ptr.read_pointer, num_tokens_ptr.read_uint
          literal
        else
          next # skip those entries for now
        end
        
        constant_location = Clang.get_cursor_location enum_constant
        constant_comment_range = Clang.get_range previous_constant_location, constant_location
        constant_comment = extract_comment translation_unit, constant_comment_range
        previous_constant_location = constant_location
        
        enum.constants << { name: constant_name, value: constant_value, comment: constant_comment }
      end
      
    when :struct_decl, :union_decl
      struct = @declarations.delete(Clang.get_cursor_type(declaration)) || StructOrUnion.new(self, name, (declaration[:kind] == :union_decl))
      raise if not struct.fields.empty?
      struct.comment << "\n#{comment}"
      
      struct_children = Clang.get_children declaration
      previous_field_end = Clang.get_cursor_location declaration
      until struct_children.empty?
        nested_declaration = [:struct_decl, :union_decl].include?(struct_children.first[:kind]) ? struct_children.shift : nil
        field = struct_children.shift
        raise if field[:kind] != :field_decl
        
        field_name = Clang.get_cursor_spelling(field).to_s_and_dispose
        field_extent = Clang.get_cursor_extent field
        
        field_comment_range = Clang.get_range previous_field_end, Clang.get_range_start(field_extent)
        field_comment = extract_comment translation_unit, field_comment_range
        
        # check for comment starting on same line
        next_field_start = struct_children.first ? Clang.get_cursor_location(struct_children.first) : Clang.get_range_end(Clang.get_cursor_extent(declaration))
        following_comment_range = Clang.get_range Clang.get_range_end(field_extent), next_field_start
        following_comment_token = extract_comment translation_unit, following_comment_range, false, false
        if following_comment_token and Clang.get_spelling_location_data(Clang.get_token_location(translation_unit, following_comment_token))[:line] == Clang.get_spelling_location_data(Clang.get_range_end(field_extent))[:line]
          field_comment = Clang.get_token_spelling(translation_unit, following_comment_token).to_s_and_dispose
          previous_field_end = Clang.get_range_end Clang.get_token_extent(translation_unit, following_comment_token)
        else
          previous_field_end = Clang.get_range_end field_extent
        end
        
        if nested_declaration
          read_named_declaration nested_declaration, ""
          decl = @declarations[Clang.get_cursor_type(nested_declaration)]
          decl.name ||= "#{name}_#{field_name}" if decl
        end
        
        field_type = Clang.get_cursor_type field
        struct.fields << { name: field_name, type: field_type, comment: field_comment }
      end
      
      @declarations[Clang.get_cursor_type(declaration)] = struct
    
    when :function_decl
      function = FunctionOrCallback.new self, name, false, @blocking.include?(name), comment
      function.return_type = Clang.get_cursor_result_type declaration
      @declarations[declaration] = function
      
      Clang.get_children(declaration).each do |function_child|
        next if function_child[:kind] != :parm_decl
        param_name = Clang.get_cursor_spelling(function_child).to_s_and_dispose
        param_type = Clang.get_cursor_type function_child
        function.parameters << { name: param_name, type: param_type}
      end
    
    when :typedef_decl
      typedef_children = Clang.get_children declaration
      if typedef_children.size == 1
        child_declaration = @declarations[Clang.get_cursor_type(typedef_children.first)]
        child_declaration.name ||= name if child_declaration
        
      elsif typedef_children.size > 1
        callback = FunctionOrCallback.new self, name, true, false, comment
        callback.return_type = Clang.get_cursor_type typedef_children.first
        @declarations[Clang.get_cursor_type(declaration)] = callback
        
        typedef_children[1..-1].each do |param_decl|
          param_name = Clang.get_cursor_spelling(param_decl).to_s_and_dispose
          param_type = Clang.get_cursor_type param_decl
          callback.parameters << { name: param_name, type: param_type }
        end
      end
        
    when :macro_definition
      tokens_ptr_ptr = FFI::MemoryPointer.new :pointer
      num_tokens_ptr = FFI::MemoryPointer.new :uint
      
      Clang.tokenize translation_unit, Clang.get_cursor_extent(declaration), tokens_ptr_ptr, num_tokens_ptr
      num_tokens = num_tokens_ptr.read_uint
      tokens_ptr = FFI::Pointer.new Clang::Token, tokens_ptr_ptr.read_pointer
      
      if num_tokens == 3
        token = Clang::Token.new tokens_ptr[1]
        if Clang.get_token_kind(token) == :literal
          value = Clang.get_token_spelling(translation_unit, token).to_s_and_dispose
          value.sub! /[A-Za-z]+$/, '' # remove number suffixes
          @declarations[name] ||= Constant.new self, name, value
        end 
      end
      
    end
  end
  
  def extract_comment(translation_unit, range, search_backwards = true, return_spelling = true)
    tokens_ptr_ptr = FFI::MemoryPointer.new :pointer
    num_tokens_ptr = FFI::MemoryPointer.new :uint
    Clang.tokenize translation_unit, range, tokens_ptr_ptr, num_tokens_ptr
    num_tokens = num_tokens_ptr.read_uint
    tokens_ptr = FFI::Pointer.new Clang::Token, tokens_ptr_ptr.read_pointer
    indices = search_backwards ? (num_tokens - 1).downto(0) : 0.upto(num_tokens - 1)
    indices.each do |i|
      token = Clang::Token.new tokens_ptr[i]
      if Clang.get_token_kind(token) == :comment
        return return_spelling ? Clang.get_token_spelling(translation_unit, token).to_s_and_dispose : token
      end
    end
    ""
  end
  
  def map_type(full_type)
    canonical_type = Clang.get_canonical_type full_type
    data_array = case canonical_type[:kind]
    when :void            then [":void",       "nil"]
    when :bool            then [":bool",       "Boolean"]
    when :u_char          then [":uchar",      "Integer"]
    when :u_short         then [":ushort",     "Integer"]
    when :u_int           then [":uint",       "Integer"]
    when :u_long          then [":ulong",      "Integer"]
    when :u_long_long     then [":ulong_long", "Integer"]
    when :char_s, :s_char then [":char",       "Integer"]
    when :short           then [":short",      "Integer"]
    when :int             then [":int",        "Integer"]
    when :long            then [":long",       "Integer"]
    when :long_long       then [":long_long",  "Integer"]
    when :float           then [":float",      "Float"]
    when :double          then [":double",     "Float"]
    when :pointer
      pointee_type = Clang.get_pointee_type canonical_type
      result = nil
      case pointee_type[:kind]
      when :char_s
        result = [":string", "String"]
      when :record
        pointee_declaration = @declarations[Clang.get_cursor_type(Clang.get_type_declaration(pointee_type))]
        result = [pointee_declaration.ruby_name, pointee_declaration.ruby_name] if pointee_declaration and pointee_declaration.written
      when :function_proto
        declaration = @declarations[full_type]
        result = [":#{declaration.ruby_name}", "Proc(_callback_#{declaration.ruby_name}_)"] if declaration
      end
      
      if result.nil?
        pointer_depth = 0
        pointer_target_name = ""
        current_type = full_type
        loop do
          declaration = Clang.get_type_declaration current_type
          pointer_target_name = to_ruby_camelcase Clang.get_cursor_spelling(declaration).to_s_and_dispose
          break if not pointer_target_name.empty?

          case current_type[:kind]
          when :pointer
            pointer_depth += 1
            current_type = Clang.get_pointee_type current_type
          when :unexposed
            break
          else
            pointer_target_name = Clang.get_type_kind_spelling(current_type[:kind]).to_s_and_dispose
            break
          end
        end
        result = [":pointer", "FFI::Pointer(#{'*' * pointer_depth}#{pointer_target_name})", pointer_target_name]
      end
      
      result
    when :record
      declaration = @declarations[canonical_type]
      declaration ? ["#{declaration.ruby_name}.by_value", declaration.ruby_name] : ["[:char, 1]", "unknown"] # TODO
    when :enum
      declaration = @declarations[canonical_type]
      [":#{declaration.ruby_name}", "Symbol from _enum_#{declaration.ruby_name}_", declaration.ruby_name]
    when :constant_array
      element_type_data = map_type Clang.get_array_element_type(canonical_type)
      size = Clang.get_array_size canonical_type
      ["[#{element_type_data[:ffi_type]}, #{size}]", "Array<#{element_type_data[:description]}>"]
    else
      raise NotImplementedError, "No translation for values of type #{canonical_type[:kind]}"
    end
    
    { ffi_type: data_array[0], description: data_array[1], parameter_name: to_ruby_lowercase(data_array[2] || data_array[1]) }
  end
  
  def to_ruby_lowercase(str, avoid_keywords = false)
    str = str.dup
    str.sub! /^(#{@prefixes.join('|')})/, '' # remove prefixes
    str.gsub! /([A-Z][a-z])/, '_\1' # add underscores before word beginnings
    str.gsub! /([a-z])([A-Z])/, '\1_\2' # add underscores after word endings
    str.sub! /^_*/, '' # remove underscores at the beginning
    str.gsub! /__+/, '_' # replace multiple underscores by only one
    str.downcase!
    str.sub! /^\d/, '_\0' # fix illegal beginnings
    str = "_#{str}" if avoid_keywords and RUBY_KEYWORDS.include? str
    str
  end
  
  def to_ruby_camelcase(str)
    str = str.dup
    str.sub! /^(#{@prefixes.join('|')})/, '' # remove prefixes
    str.gsub!(/(^|_)[a-z]/) { |match| match.upcase } # make word beginnings upcased
    str.gsub! '_', '' # remove all underscores
    str
  end
  
  def self.generate(options = {})
    self.new(options).generate
  end
  
end

if __FILE__ == $0
  FFIGen.generate(
    ruby_module: "FFIGen::Clang",
    ffi_lib:     "clang",
    headers:     ["clang-c/Index.h"],
    cflags:      `llvm-config --cflags`.split(" "),
    prefixes:    ["clang_", "CX"],
    blacklist:   ["clang_getExpansionLocation"],
    output:      File.join(File.dirname(__FILE__), "ffi_gen/clang.rb")
  )
end
