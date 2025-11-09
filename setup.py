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
    print(f"DEBUG setup.py: _SKBUILD_PLAT_NAME = {os.environ.get('_SKBUILD_PLAT_NAME', 'NOT SET')}", file=sys.stderr)

# CRITICAL: Import scikit-build AFTER setting _SKBUILD_PLAT_NAME
# scikit-build checks os.environ.get('_SKBUILD_PLAT_NAME') in constants.py at import time
from skbuild import setup
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
