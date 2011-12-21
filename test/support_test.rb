require "test_helper"

class SupportTest < Test::Unit::TestCase

  def setup
    LLVM.init_x86
  end

  def test_load_library_status
    libm = File.join("/usr/lib", FFI.map_library_name("libm"))
    assert_equal true, LLVM.load_library(libm)
    assert_equal false, LLVM.load_library("/nogood")
  end
end
