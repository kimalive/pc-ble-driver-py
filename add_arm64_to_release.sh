#!/bin/bash
# Helper script to add ARM64 wheels to a GitHub release
# This script helps you upload locally-built ARM64 wheels to an existing release

set -e

VERSION=${1:-"0.17.11"}
TAG="v${VERSION}"

echo "=================================================================================="
echo "Add ARM64 Wheels to GitHub Release"
echo "=================================================================================="
echo ""
echo "Release: ${TAG} (version ${VERSION})"
echo ""

# Check if ARM64 wheels exist
ARM64_WHEELS=$(ls dist/*arm64*.whl 2>/dev/null || echo "")
if [ -z "$ARM64_WHEELS" ]; then
    echo "❌ No ARM64 wheels found in dist/"
    echo ""
    echo "Build ARM64 wheels first:"
    echo "  ./build_wheels.sh"
    exit 1
fi

echo "✅ Found ARM64 wheels:"
ls -lh dist/*arm64*.whl | awk '{print "  " $9 " (" $5 ")"}'
echo ""

# Count wheels
WHEEL_COUNT=$(ls dist/*arm64*.whl 2>/dev/null | wc -l | tr -d ' ')
echo "Total ARM64 wheels: ${WHEEL_COUNT}"
echo ""

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "⚠️  GitHub CLI (gh) not found"
    echo ""
    echo "Manual steps:"
    echo "1. Go to: https://github.com/kimalive/pc-ble-driver-py/releases/tag/${TAG}"
    echo "2. Click 'Edit release'"
    echo "3. Drag & drop these ARM64 wheels:"
    ls dist/*arm64*.whl | while read wheel; do
        echo "   - $(basename $wheel)"
    done
    echo "4. Click 'Update release'"
    echo ""
    exit 0
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "⚠️  Not authenticated with GitHub CLI"
    echo ""
    echo "Run: gh auth login"
    echo ""
    exit 1
fi

# Check if release exists
if ! gh release view "${TAG}" &> /dev/null; then
    echo "❌ Release ${TAG} does not exist"
    echo ""
    echo "Create it first, or use the GitHub Actions release workflow"
    exit 1
fi

echo "Release ${TAG} exists. Uploading ARM64 wheels..."
echo ""

# Upload each ARM64 wheel
UPLOADED=0
FAILED=0

for wheel in dist/*arm64*.whl; do
    if [ -f "$wheel" ]; then
        wheel_name=$(basename "$wheel")
        echo -n "Uploading ${wheel_name}... "
        
        if gh release upload "${TAG}" "$wheel" --clobber 2>/dev/null; then
            echo "✅"
            ((UPLOADED++))
        else
            echo "❌ Failed"
            ((FAILED++))
        fi
    fi
done

echo ""
echo "=================================================================================="
echo "Upload Summary"
echo "=================================================================================="
echo "Uploaded: ${UPLOADED}"
echo "Failed: ${FAILED}"
echo ""

if [ ${FAILED} -eq 0 ]; then
    echo "✅ All ARM64 wheels uploaded successfully!"
    echo ""
    echo "View release: https://github.com/kimalive/pc-ble-driver-py/releases/tag/${TAG}"
else
    echo "⚠️  Some uploads failed. Try uploading manually via GitHub web interface."
fi
echo ""

