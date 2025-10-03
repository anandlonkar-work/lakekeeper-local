#!/bin/bash
# Quick build status checker

echo "🔨 Build Status Check"
echo "====================="
echo ""

if [ ! -f /tmp/fgac-build.log ]; then
    echo "❌ No build log found at /tmp/fgac-build.log"
    echo "Start build with: cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-local && cargo build --release"
    exit 1
fi

# Check if build is complete
if grep -q "Finished" /tmp/fgac-build.log; then
    echo "✅ Build Complete!"
    echo ""
    grep "Finished" /tmp/fgac-build.log
    echo ""
    echo "Next step: Restart Docker services"
    echo "  cd examples/access-control-advanced"
    echo "  docker-compose down"
    echo "  docker-compose up -d"
elif grep -q "error" /tmp/fgac-build.log; then
    echo "❌ Build Failed!"
    echo ""
    echo "Errors found:"
    grep -A 3 "error" /tmp/fgac-build.log | tail -20
else
    echo "⏳ Build In Progress..."
    echo ""
    echo "Currently compiling:"
    tail -5 /tmp/fgac-build.log | grep "Compiling" | tail -3
    echo ""
    echo "Total lines in log: $(wc -l < /tmp/fgac-build.log)"
    echo ""
    echo "Run this script again to check status"
fi
