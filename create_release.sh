#!/bin/bash
# Helper script to create a release with wheels

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [tag]"
    echo "Example: $0 0.17.10 v0.17.10"
    exit 1
fi

VERSION=$1
TAG=${2:-v$VERSION}

echo "=================================================================================="
echo "Creating Release: $VERSION (tag: $TAG)"
echo "=================================================================================="
echo ""

# Check if tag exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "✓ Tag $TAG already exists"
else
    echo "Creating tag $TAG..."
    git tag "$TAG"
    git push origin "$TAG"
    echo "✓ Tag created and pushed"
fi

echo ""
echo "=================================================================================="
echo "Next Steps:"
echo "=================================================================================="
echo ""
echo "1. Build ARM64 wheels locally (if not already built):"
echo "   ./build_wheels.sh"
echo ""
echo "2. Trigger GitHub Actions release workflow:"
echo "   - Go to: https://github.com/kimalive/pc-ble-driver-py/actions"
echo "   - Click 'Create Release with Wheels'"
echo "   - Click 'Run workflow'"
echo "   - Enter Version: $VERSION"
echo "   - Enter Tag: $TAG"
echo "   - Click 'Run workflow'"
echo ""
echo "3. After x86_64 wheels are built, add ARM64 wheels:"
echo "   - Go to: https://github.com/kimalive/pc-ble-driver-py/releases/tag/$TAG"
echo "   - Click 'Edit release'"
echo "   - Drag & drop ARM64 wheels from dist/ folder"
echo "   - Click 'Update release'"
echo ""
echo "4. Use in requirements.txt:"
echo "   # For x86_64 (Intel Mac)"
echo "   pc_ble_driver_py @ https://github.com/kimalive/pc-ble-driver-py/releases/download/$TAG/pc_ble_driver_py-$VERSION-cp312-abi3-macosx_26_0_x86_64.whl"
echo ""
echo "   # For ARM64 (Apple Silicon)"
echo "   pc_ble_driver_py @ https://github.com/kimalive/pc-ble-driver-py/releases/download/$TAG/pc_ble_driver_py-$VERSION-cp312-abi3-macosx_26_0_arm64.whl"
echo ""
echo "=================================================================================="

