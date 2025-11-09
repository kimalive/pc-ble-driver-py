#
# Copyright (c) 2016-2019 Nordic Semiconductor ASA
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
#   1. Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
#   2. Redistributions in binary form must reproduce the above copyright notice, this
#   list of conditions and the following disclaimer in the documentation and/or
#   other materials provided with the distribution.
#
#   3. Neither the name of Nordic Semiconductor ASA nor the names of other
#   contributors to this software may be used to endorse or promote products
#   derived from this software without specific prior written permission.
#
#   4. This software must only be used in or with a processor manufactured by Nordic
#   Semiconductor ASA, or in or with a processor manufactured by a third party that
#   is used in combination with a processor manufactured by Nordic Semiconductor.
#
#   5. Any software provided in binary or object form under this license must not be
#   reverse engineered, decompiled, modified and/or disassembled.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
import sys
import re
import codecs
import os
import importlib.util
import types

# CRITICAL: Set _SKBUILD_PLAT_NAME before importing scikit-build
# This fixes the ValueError when scikit-build tries to parse macOS version
# scikit-build expects platform.release() to return "X.Y" but newer macOS returns "X"
# We MUST set this before any scikit-build imports, as it's checked at module import time
# scikit-build checks os.environ.get('_SKBUILD_PLAT_NAME') in constants.py at import time
if sys.platform == "darwin":
    # Only set if not already set (allow environment variable to override)
    if "_SKBUILD_PLAT_NAME" not in os.environ:
        import platform
        try:
            # Try to get macOS version from platform.mac_ver() (most reliable)
            macos_version = platform.mac_ver()[0]  # e.g., "15.7.1" or "15.7"
            if macos_version:
                parts = macos_version.split(".")
                major = parts[0] if len(parts) > 0 else "15"
                minor = parts[1] if len(parts) > 1 else "0"
            else:
                # Fallback if mac_ver() returns empty
                major, minor = "15", "0"
        except Exception:
            # Fallback if platform.mac_ver() fails
            major, minor = "15", "0"
        
        # Get architecture
        try:
            arch = platform.machine()  # e.g., "arm64" or "x86_64"
        except Exception:
            arch = "arm64"  # Default to arm64 for macOS
        
        # Set the environment variable
        if arch == "arm64":
            os.environ["_SKBUILD_PLAT_NAME"] = f"macosx-{major}.{minor}-arm64"
        else:
            os.environ["_SKBUILD_PLAT_NAME"] = f"macosx-{major}.{minor}-x86_64"
    
    # CRITICAL: Verify it's set before importing scikit-build
    # This ensures scikit-build will find it when it checks os.environ.get()
    if "_SKBUILD_PLAT_NAME" not in os.environ:
        # Last resort fallback
        import platform
        arch = platform.machine() if hasattr(platform, 'machine') else "arm64"
        if arch == "arm64":
            os.environ["_SKBUILD_PLAT_NAME"] = "macosx-15.0-arm64"
        else:
            os.environ["_SKBUILD_PLAT_NAME"] = "macosx-15.0-x86_64"
    
    # DEBUG: Print the value to verify it's set (remove in production if needed)
    plat_name = os.environ.get('_SKBUILD_PLAT_NAME', 'NOT SET')
    print(f"DEBUG setup.py: _SKBUILD_PLAT_NAME = {plat_name}", file=sys.stderr)
    
    # CRITICAL: Force set it again right before import to ensure it's definitely there
    # Sometimes environment variables can be lost or not properly inherited
    if plat_name != 'NOT SET':
        # Re-set it to ensure it's definitely in the environment dict
        os.environ["_SKBUILD_PLAT_NAME"] = plat_name
        print(f"DEBUG setup.py: Re-verified _SKBUILD_PLAT_NAME = {plat_name}", file=sys.stderr)
    else:
        # Emergency fallback - should never happen but just in case
        import platform
        arch = platform.machine() if hasattr(platform, 'machine') else "arm64"
        fallback = f"macosx-15.0-{arch}"
        os.environ["_SKBUILD_PLAT_NAME"] = fallback
        print(f"DEBUG setup.py: EMERGENCY FALLBACK - set _SKBUILD_PLAT_NAME = {fallback}", file=sys.stderr)
    
    # CRITICAL: scikit-build's constants.py calls _default_skbuild_plat_name() at module import time
    # which uses platform.release(). On newer macOS, platform.release() returns "15" (no dot),
    # causing ValueError: not enough values to unpack (expected 2, got 1)
    # 
    # The issue: scikit-build does: release = platform.release(); major, minor = release.split(".")[:2]
    # If release is "15" (no dot), split(".") returns ["15"], causing the ValueError
    # 
    # Solution: Patch platform.release() to always return a value with at least one dot
    # We must patch it in multiple places to ensure scikit-build sees it
    
    import platform
    
    # Store the original function
    original_release = platform.release
    
    def patched_release():
        """Return a safe macOS version string that scikit-build can parse"""
        try:
            # Get the actual release value
            release = original_release()
            # scikit-build expects "X.Y" format, so ensure we have at least one dot
            if not release:
                return "15.0"
            # Split by dot to check format
            parts = release.split(".")
            if len(parts) >= 2:
                # Already has major.minor, return as-is
                return release
            elif len(parts) == 1:
                # Only major version (e.g., "15"), append ".0"
                return f"{parts[0]}.0"
            else:
                # Empty or weird, use fallback
                return "15.0"
        except Exception as e:
            # Fallback on any error
            print(f"DEBUG setup.py: platform.release() error: {e}, using fallback", file=sys.stderr)
            return "15.0"
    
    # CRITICAL: Patch it in the platform module BEFORE importing scikit-build
    # This must happen before any scikit-build code runs
    platform.release = patched_release
    
    # CRITICAL: Also patch it in sys.modules['platform'] to ensure all imports see it
    # This is necessary because Python caches module imports
    if 'platform' in sys.modules:
        sys.modules['platform'].release = patched_release
    
    # CRITICAL: Also patch it in the builtins module (platform is a builtin)
    # This ensures the patch is visible even if scikit-build imports platform differently
    import builtins
    if hasattr(builtins, 'platform'):
        builtins.platform = platform
    
    # Verify the patch works
    test_release = platform.release()
    print(f"DEBUG setup.py: Patched platform.release() = {test_release!r}", file=sys.stderr)
    print(f"DEBUG setup.py: sys.modules['platform'].release = {sys.modules['platform'].release()!r}", file=sys.stderr)
    
    # Store patched_release for potential retry
    globals()['_patched_release_func'] = patched_release

# CRITICAL: Import scikit-build AFTER setting _SKBUILD_PLAT_NAME and patching platform.release()
# scikit-build's constants.py calls _default_skbuild_plat_name() which uses platform.release()
# Our patch ensures platform.release() returns a parseable value
#
# However, scikit-build imports platform in its own module context, so we need to patch
# the actual function that scikit-build will call. We'll use an import hook to intercept
# scikit-build's constants module and patch _default_skbuild_plat_name() directly.

# First, try to import and patch scikit-build's constants module before it executes
try:
    # Import the constants module's parent to get access to it
    import importlib
    import types
    
    # Try to load skbuild.constants and patch _default_skbuild_plat_name before it runs
    # We need to do this carefully because the module executes at import time
    skbuild_spec = importlib.util.find_spec('skbuild')
    if skbuild_spec and skbuild_spec.submodule_search_locations:
        # We found skbuild, now try to patch constants before it's imported
        constants_path = None
        for location in skbuild_spec.submodule_search_locations:
            potential_path = os.path.join(location, 'constants.py')
            if os.path.exists(potential_path):
                constants_path = potential_path
                break
        
        if constants_path:
            # Read the constants.py file and patch it in memory
            with open(constants_path, 'r') as f:
                constants_code = f.read()
            
            # Patch the _default_skbuild_plat_name function to handle single-digit releases
            # Find the function and wrap it
            if '_default_skbuild_plat_name' in constants_code:
                # Create a patched version that handles the error
                # Try multiple possible variations of the problematic line
                problematic_patterns = [
                    'major_macos, minor_macos = release.split(".")[:2]',
                    "major_macos, minor_macos = release.split('.')[:2]",
                    'major_macos, minor_macos = release.split(".")[:2]  #',
                    "major_macos, minor_macos = release.split('.')[:2]  #",
                ]
                
                patched_constants_code = constants_code
                replacement_applied = False
                
                for pattern in problematic_patterns:
                    if pattern in patched_constants_code:
                        patched_constants_code = patched_constants_code.replace(
                            pattern,
                            '''# Patched by setup.py to handle single-digit macOS releases
parts = release.split(".")
if len(parts) < 2:
    release = f"{parts[0]}.0" if parts else "15.0"
major_macos, minor_macos = release.split(".")[:2]'''
                        )
                        replacement_applied = True
                        print(f"DEBUG setup.py: Patched pattern: {pattern[:50]}...", file=sys.stderr)
                        break
                
                if not replacement_applied:
                    print("DEBUG setup.py: WARNING: Could not find problematic line pattern in constants.py", file=sys.stderr)
                    print("DEBUG setup.py: Will attempt to patch at function level instead", file=sys.stderr)
                
                # Execute the patched code in a new module
                constants_module = types.ModuleType('skbuild.constants')
                exec(compile(patched_constants_code, constants_path, 'exec'), constants_module.__dict__)
                sys.modules['skbuild.constants'] = constants_module
                print("DEBUG setup.py: Patched skbuild.constants module in memory", file=sys.stderr)
except Exception as e:
    print(f"DEBUG setup.py: Could not patch skbuild.constants directly: {e}", file=sys.stderr)
    # Fall back to normal import

# Now try to import scikit-build
try:
    from skbuild import setup
except ValueError as e:
    if "not enough values to unpack" in str(e):
        # The patch didn't work, try one more time with a different approach
        print("DEBUG setup.py: Import still failed, trying final fallback", file=sys.stderr)
        # Force set the environment variable that scikit-build should check
        # (even though it doesn't seem to check it, maybe a newer version does)
        os.environ['_SKBUILD_PLAT_NAME'] = 'macosx-15.0-arm64' if platform.machine() == 'arm64' else 'macosx-15.0-x86_64'
        # Try importing again
        from skbuild import setup
    else:
        raise
from setuptools import find_packages

if sys.version_info < (3, 6):
    print("pc-ble-driver-py only supports Python version 3.6 and newer")
    sys.exit(-1)

requirements = ["wrapt", "cryptography"]

if os.path.exists("MANIFEST"):
    os.remove("MANIFEST")

here = os.path.abspath(os.path.dirname(__file__))


def read(*parts):
    # intentionally *not* adding an encoding option to open, See:
    #   https://github.com/pypa/virtualenv/issues/201#issuecomment-3145690
    with codecs.open(os.path.join(here, *parts), "r") as fp:
        return fp.read()


def find_version(*file_paths):
    version_file = read(*file_paths)
    version_match = re.search(
        r"^__version__ = ['\"]([^'\"]*)['\"]", version_file, re.M,
    )
    if version_match:
        return version_match.group(1)

    raise RuntimeError("Unable to find version string.")


packages = find_packages(exclude=["tests*"])

setup(
    name="pc_ble_driver_py",
    version=find_version("pc_ble_driver_py", "__init__.py"),
    description="Python bindings for the Nordic pc-ble-driver SoftDevice serialization library",
    long_description=read("README.md"),
    long_description_content_type="text/markdown",
    url="https://github.com/NordicSemiconductor/pc-ble-driver-py",
    license="Modified BSD License",
    author="Nordic Semiconductor ASA",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Operating System :: MacOS",
        "Operating System :: Microsoft :: Windows",
        "Operating System :: POSIX :: Linux",
        "Topic :: System :: Networking",
        "Topic :: System :: Hardware :: Hardware Drivers",
        "Topic :: Software Development :: Embedded Systems",
        # Note: License classifier removed (deprecated by setuptools)
        # License is specified via the 'license' parameter above and in pyproject.toml
        "Programming Language :: Python",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: 3.13",
    ],
    keywords="nordic nrf51 nrf52 ble bluetooth softdevice serialization bindings pc-ble-driver pc-ble-driver-py "
    "pc_ble_driver pc_ble_driver_py",
    python_requires=">=3.7",
    install_requires=requirements,
    packages=packages,
    package_data={
        "pc_ble_driver_py.lib": ["*.pyd", "*.dll", "*.txt", "*.so", "*.dylib"],
        "pc_ble_driver_py.hex": ["*.hex"],
        "pc_ble_driver_py.hex.sd_api_v2": ["*.hex"],
        "pc_ble_driver_py.hex.sd_api_v5": ["*.hex", "*.zip"],
    },
)
