require "fileutils"
require "ffi_gen"

def run_test(options = {})
  options[:file_mappings].each do |header, ruby_file|
    output_file = File.join File.dirname(__FILE__), "gen/#{options[:library_name]}/#{ruby_file}"
    FileUtils.mkdir_p File.dirname(output_file)
    
    FFIGen.generate(
      ruby_module: options[:library_name],
      ffi_lib:     options[:ffi_lib],
      headers:     [header],
      cflags:      options.fetch(:cflags, []),
      prefixes:    options.fetch(:prefixes, []),
      blacklist:   options.fetch(:blacklist, []),
      blocking:    options.fetch(:blocking, []),
      output:      output_file
    )
    
    require output_file
  end
  
  puts "#{options[:library_name]} test successful"
end
