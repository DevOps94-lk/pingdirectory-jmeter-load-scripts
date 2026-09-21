#!/usr/bin/env bash
# Test 2 - breaking point
source "$(dirname "$0")/common.sh"
echo ">> Running Test 2 (breaking point). Report will be out/test2/report/index.html"
echo ">> It KEEPS CLIMBING (max pd.durationSec, default 2h) - press Ctrl-C once when PingDirectory starts failing; the report is still built."
echo ">> Watch: kubectl get pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory -o wide -w"
run_test test2 pingdir-test2-breakingpoint.jmx
