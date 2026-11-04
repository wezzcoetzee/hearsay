#!/bin/sh
# Lint Swift sources with swift-format. Pass --fix to format in place.
set -e
cd "$(dirname "$0")/.."
if [ "$1" = "--fix" ]; then
    swift format --in-place --recursive --parallel Package.swift Sources Tests
fi
swift format lint --strict --recursive --parallel Package.swift Sources Tests
