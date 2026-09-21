#!/usr/bin/env bash
# Test 1 - sustained, ~30 min
source "$(dirname "$0")/common.sh"
echo ">> Running Test 1 (sustained, ~30 min). Report will be out/test1/report/index.html"
run_test test1 pingdir-test1-sustained.jmx
