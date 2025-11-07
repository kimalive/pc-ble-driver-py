#!/bin/bash
# Create Universal2 wheels from separate ARM64 and x86_64 wheels for each Python version
# This combines architectures but keeps Python versions separate

set -e

echo "=================================================================================="
echo "Creating Universal2 wheels for all Python versions"
echo "=================================================================================="
echo ""

PYTHON_VERSIONS=("3.8" "3.9" "3.10" "3.11" "3.12" "3.13")
CREATED=0
MISSING=0

for version in "${PYTHON_VERSIONS[@]}"; do
    python_tag="cp${version//./}"
    
    echo "Processing Python ${version} (${python_tag})..."
    
    # Find ARM64 and x86_64 wheels for this Python version
    arm64_wheel=$(ls dist/*${python_tag}-abi3-*arm64*.whl 2>/dev/null | head -1)
    x86_64_wheel=$(ls dist/*${python_tag}-abi3-*x86_64*.whl 2>/dev/null | head -1)
    
    # Also check for wheels without architecture suffix (standard wheel names)
    if [ -z "$arm64_wheel" ]; then
        # Try to find any wheel for this Python version and check its architecture
        any_wheel=$(ls dist/*${python_tag}-abi3-*.whl 2>/dev/null | grep -v universal | head -1)
        if [ -n "$any_wheel" ]; then
            # Check if it's ARM64 or x86_64
            arch_check=$(file "$any_wheel" 2>/dev/null || echo "")
            if [[ "$arch_check" == *"arm64"* ]] || [[ "$arch_check" == *"ARM64"* ]]; then
                arm64_wheel="$any_wheel"
            elif [[ "$arch_check" == *"x86_64"* ]] || [[ "$arch_check" == *"Intel"* ]]; then
                x86_64_wheel="$any_wheel"
            fi
        fi
    fi
    
    if [ -z "$arm64_wheel" ] && [ -z "$x86_64_wheel" ]; then
        echo "  ⚠️  No wheels found for Python ${version}"
        ((MISSING++))
        continue
    fi
    
    # Determine output name
    if [ -n "$arm64_wheel" ]; then
        base_name=$(basename "$arm64_wheel" | sed 's/_arm64\.whl$/.whl/' | sed 's/\.whl$/_universal2.whl/')
    elif [ -n "$x86_64_wheel" ]; then
        base_name=$(basename "$x86_64_wheel" | sed 's/_x86_64\.whl$/.whl/' | sed 's/\.whl$/_universal2.whl/')
    fi
    
    output_wheel="dist/${base_name}"
    
    # If we only have one architecture, we can't create Universal2
    if [ -z "$arm64_wheel" ] || [ -z "$x86_64_wheel" ]; then
        if [ -n "$arm64_wheel" ]; then
            echo "  ℹ️  Only ARM64 wheel available (${arm64_wheel})"
            echo "     Universal2 requires both ARM64 and x86_64 wheels"
        elif [ -n "$x86_64_wheel" ]; then
            echo "  ℹ️  Only x86_64 wheel available (${x86_64_wheel})"
            echo "     Universal2 requires both ARM64 and x86_64 wheels"
        fi
        continue
    fi
    
    echo "  ARM64: $(basename $arm64_wheel)"
    echo "  x86_64: $(basename $x86_64_wheel)"
    echo "  Output: $(basename $output_wheel)"
    
    # Use create_universal2_wheel.sh to combine
    if ./create_universal2_wheel.sh "$arm64_wheel" "$x86_64_wheel" "$output_wheel" 2>&1 | grep -v "^$" | tail -3; then
        echo "  ✓ Created Universal2 wheel"
        ((CREATED++))
    else
        echo "  ✗ Failed to create Universal2 wheel"
    fi
    
    echo ""
done

echo "=================================================================================="
echo "Summary"
echo "=================================================================================="
echo "Universal2 wheels created: $CREATED"
echo "Missing wheels: $MISSING"
echo ""
echo "Universal2 wheels in dist/:"
ls -lh dist/*universal2*.whl 2>/dev/null | awk '{print $9, "(" $5 ")"}' || echo "No Universal2 wheels found"

