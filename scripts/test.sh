#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swiftc Sources/CloudLens/Imaging.swift Tests/CloudLensTests/ImagingTests.swift -o .build/imaging-checks
.build/imaging-checks
