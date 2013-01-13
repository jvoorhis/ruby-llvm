require "test_utils"

run_test(
  library_name:  "GL",
  ffi_lib:       "GL",
  prefixes:      ["gl", "GL_"],
  blacklist:     lambda { |name| name.end_with?("MESA") || name.end_with?("ATI") },
  file_mappings: {
    "GL/gl.h" => "gl.rb"
  }
)

run_test(
  library_name:  "GLU",
  ffi_lib:       "GLU",
  prefixes:      ["glu", "GLU_"],
  file_mappings: {
    "GL/glu.h" => "glu.rb"
  }
)

run_test(
  library_name:  "GLUT",
  ffi_lib:       "glut",
  prefixes:      ["glut", "GLUT_"],
  file_mappings: {
    "GL/freeglut_std.h" => "glut.rb"
  }
)