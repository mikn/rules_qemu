#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

TAG="${1:?Usage: release_prep.sh <tag>}"
PREFIX="rules_qemu-${TAG:1}"
ARCHIVE="rules_qemu-${TAG}.tar.gz"

# Verify MODULE.bazel version matches tag
module_version=$(grep -oP 'version = "\K[^"]+' MODULE.bazel)
if [ "$module_version" != "${TAG:1}" ]; then
  echo "ERROR: MODULE.bazel version ($module_version) does not match tag ($TAG)" >&2
  exit 1
fi

git archive --format=tar --prefix="${PREFIX}/" "${TAG}" | gzip > "$ARCHIVE"

cat <<EOF
## rules_qemu ${TAG}

Bazel toolchains for QEMU and swtpm.

\`\`\`starlark
bazel_dep(name = "rules_qemu", version = "${TAG:1}")
\`\`\`
EOF
