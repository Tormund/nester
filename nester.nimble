version       = "0.2.0"
author        = "Volodymyr Melnychuk"
description   = "Simple HTTP server"
license       = "MIT"

srcDir        = "src"
bin           = @["nestd"]
installExt    = @["nim"]

requires "nim >= 0.20.0"
requires "https://github.com/kedean/nest"
requires "cligen"