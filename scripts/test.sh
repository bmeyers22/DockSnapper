#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path build/module-cache Sources/Geometry.swift Tests/main.swift -o build/geometry-tests
build/geometry-tests
