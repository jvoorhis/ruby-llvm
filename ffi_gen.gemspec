Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY

  s.name = "ffi_gen"
  s.version = "1.0.2"
  s.summary = "A generator for Ruby FFI bindings"
  s.description = "A generator for Ruby FFI bindings, directly from header files via LLVM's Clang compiler"
  s.author = "Richard Musiol"
  s.email = "mail@richard-musiol.de"
  s.homepage = "https://github.com/neelance/ffi_gen"

  s.add_dependency "ffi", ">= 1.0.0"
  s.files = Dir["lib/**/*.rb"] + ["LICENSE", "README.md", "lib/ffi_gen/empty.h"]
  s.require_path = "lib"
end