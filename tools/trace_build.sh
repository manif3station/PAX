#!/bin/sh
# Builds an instrumented copy of the dashboard binary that appends the name of every handler-compiled
# sub to $PAX_OP_TRACE_FILE the first time it runs.  Usage: tools/trace_build.sh OUT_BINARY [APP_DIR]
# Compare the trace with the list of handler-compiled subs to see which ones a scenario never reaches.
set -e
OUT=$1; APP=${2:-$(cd "$(dirname "$0")/../../developer-dashboard" && pwd)}
SRC=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
cp -r "$SRC/bin" "$SRC/lib" "$TMP/"
perl -0pi -e 's/(    my \(\$package, \$name, \$prototype, \$impl\) = \@_;\n    my \$full = \$package \. .::. \. \$name;)/$1\n    if (defined \$ENV{PAX_OP_TRACE_FILE}) {\n        my \$inner = \$impl; my \$seen = 0;\n        \$impl = sub { if (!\$seen++) { if (open my \$tfh, ">>", \$ENV{PAX_OP_TRACE_FILE}) { print {\$tfh} "\$full\\n"; close \$tfh } } return &\$inner };\n    }/' "$TMP/lib/PAX/StandaloneRuntime.pm"
grep -q PAX_OP_TRACE_FILE "$TMP/lib/PAX/StandaloneRuntime.pm" || { echo "could not instrument the runtime" >&2; exit 1; }
WORK=$(mktemp -d)
( cd "$WORK" && PAX_PROGRESS=0 perl "$TMP/bin/pax" build --compact -o "$OUT" "$APP/bin/dashboard" >/dev/null 2>&1 )
rm -rf "$TMP" "$WORK"
echo "$OUT"
