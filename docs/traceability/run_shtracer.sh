#!/bin/bash

SCRIPT_DIR=${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}
cd "$SCRIPT_DIR" || exit 1
../shtracer/shtracer ./config.md --html >./traceability.html
