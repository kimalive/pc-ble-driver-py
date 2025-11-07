#!/usr/bin/env python3
"""
Post-process wheel to make it work with all Python 3.8+ versions.

Changes @rpath/libpython3.X.dylib to @rpath/Python (framework style)
so it works with any Python version.
"""
import sys
import zipfile
import tempfile
import os
import subprocess
from pathlib import Path

def fix_so_file(so_path):
    """Fix .so file to use @rpath/Python instead of version-specific library."""
    # Check current dependencies
    result = subprocess.run(
        ['otool', '-L', so_path],
        capture_output=True,
        text=True,
        check=True
    )
    
    changes_needed = []
    for line in result.stdout.split('\n'):
        if '@rpath/libpython' in line and '.dylib' in line:
            # Extract the old reference
            old_ref = line.strip().split()[0]
            # Change to framework style
            new_ref = '@rpath/Python'
            changes_needed.append((old_ref, new_ref))
    
    # Apply changes
    for old_ref, new_ref in changes_needed:
        print(f"  Changing {old_ref} -> {new_ref}")
        subprocess.run(
            ['install_name_tool', '-change', old_ref, new_ref, so_path],
            check=True
        )
    
    return len(changes_needed) > 0

def fix_wheel(wheel_path):
    """Fix wheel to work with all Python versions."""
    print(f"Processing wheel: {wheel_path}")
    
    # Create temporary directory
    with tempfile.TemporaryDirectory() as temp_dir:
        # Extract wheel
        print("Extracting wheel...")
        with zipfile.ZipFile(wheel_path, 'r') as z:
            z.extractall(temp_dir)
        
        # Find and fix .so files
        so_files = list(Path(temp_dir).rglob('*.so'))
        print(f"Found {len(so_files)} .so files")
        
        fixed_any = False
        for so_file in so_files:
            print(f"\nFixing {so_file.relative_to(temp_dir)}...")
            if fix_so_file(str(so_file)):
                fixed_any = True
        
        if not fixed_any:
            print("\nNo changes needed (already using @rpath/Python or no Python dependencies)")
            return
        
        # Recreate wheel
        print(f"\nRecreating wheel...")
        output_path = Path(wheel_path)
        backup_path = output_path.with_suffix('.whl.backup')
        
        # Backup original
        if output_path.exists():
            import shutil
            shutil.copy2(output_path, backup_path)
            print(f"Backed up original to {backup_path}")
        
        # Create new wheel
        with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as z:
            for root, dirs, files in os.walk(temp_dir):
                for file in files:
                    file_path = Path(root) / file
                    arc_name = file_path.relative_to(temp_dir)
                    z.write(file_path, arc_name)
        
        print(f"✓ Fixed wheel: {output_path}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix_wheel_python_version.py <wheel.whl>")
        sys.exit(1)
    
    fix_wheel(sys.argv[1])

