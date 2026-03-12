#!/usr/bin/env bash
# Verify systemd service file content from within a tar.
# Usage: verify_service.sh <tar_file>
#
# Extracts vmtest-agent.service from the tar and checks key directives.

set -euo pipefail

TAR="$1"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Extract the service file
tar xf "$TAR" -C "$TMPDIR" etc/systemd/system/vmtest-agent.service

SERVICE="$TMPDIR/etc/systemd/system/vmtest-agent.service"

if [[ ! -f "$SERVICE" ]]; then
    echo "FAIL: vmtest-agent.service not found in tar"
    exit 1
fi

FAILURES=0

# Check ExecStart points to the correct binary
if ! grep -q '^ExecStart=/usr/lib/vmtest/agent$' "$SERVICE"; then
    echo "FAIL: ExecStart does not reference /usr/lib/vmtest/agent"
    echo "  Actual ExecStart line:"
    grep 'ExecStart' "$SERVICE" || echo "  (not found)"
    FAILURES=$((FAILURES + 1))
fi

# Check Type=simple
if ! grep -q '^Type=simple$' "$SERVICE"; then
    echo "FAIL: Type is not 'simple'"
    echo "  Actual Type line:"
    grep 'Type' "$SERVICE" || echo "  (not found)"
    FAILURES=$((FAILURES + 1))
fi

# Check WantedBy=multi-user.target (install section)
if ! grep -q '^WantedBy=multi-user.target$' "$SERVICE"; then
    echo "FAIL: WantedBy is not 'multi-user.target'"
    echo "  Actual WantedBy line:"
    grep 'WantedBy' "$SERVICE" || echo "  (not found)"
    FAILURES=$((FAILURES + 1))
fi

if [[ $FAILURES -gt 0 ]]; then
    echo ""
    echo "$FAILURES assertion(s) failed"
    echo ""
    echo "=== Full service file ==="
    cat "$SERVICE"
    exit 1
fi

echo "All service file assertions passed"
