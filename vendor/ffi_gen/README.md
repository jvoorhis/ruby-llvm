ffi_gen - A generator for Ruby FFI bindings
===========================================

*Author:* Richard Musiol  
*Contributors:* Jeremy Voorhis (thanks for the initial idea)  
*License:* MIT (see LICENSE)


Features
--------
* Generation of FFI methods, structures, unions, enumerations and callbacks
* Generation of YARD documentation comments
* Tested with headers of the following libraries:
  * Clang
  * LLVM
  * OpenGL
  * SQLite3
  * Cairo


Requirements
------------

* Ruby 1.9
* Clang 3.0 ([Download](http://llvm.org/releases/download.html#3.0), use the binaries or configure with ``--enable-shared``)

*These requirements are only for running the generator. The generated files are Ruby 1.8 compatible and do not need Clang.*


Example
-------
Use the following interface in a script or Rake task:

    require "ffi_gen"
    
    FFIGen.generate(
      ruby_module: "Clang",
      ffi_lib:     "clang",
      headers:     ["clang-c/Index.h"],
      cflags:      `llvm-config --cflags`.split(" "),
      prefixes:    ["clang_", "CX"],
      blacklist:   ["clang_getExpansionLocation"],
      output:      "Clang/index.rb"
    )

Output: [Clang/index.rb](https://github.com/neelance/ffi_gen/blob/master/test/gen/Clang/index.rb)

Other generated files can be found in the [test/gen](https://github.com/neelance/ffi_gen/tree/master/test/gen) directory.


Hints
-----

You may need to set additional include directories:

    export CPATH=/usr/lib/gcc/x86_64-linux-gnu/4.6.1/include

Your GCC include paths can be seen with:

    `gcc -print-prog-name=cc1` -v


Projects using ffi_gen
----------------------

* https://github.com/jvoorhis/ruby-llvm


Roadmap
-------

* Support for more libraries:
  * (Write me if you have a whish)
* Automatic generation of object oriented wrappers
* Polish YARD documentation comments some more


Feedback
--------
Please use GitHub's issue tracker for problems or suggestions. Pull requests are welcome, too.