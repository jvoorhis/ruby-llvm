require "test_utils"

run_test(
  library_name:  "SQLite3",
  ffi_lib:       "sqlite3",
  prefixes:      ["sqlite3_", "SQLITE_"],
  blacklist:     ["sqlite3_mutex_held", "sqlite3_mutex_notheld"],
  file_mappings: {
    "sqlite3.h" => "sqlite3.rb"
  }
)
