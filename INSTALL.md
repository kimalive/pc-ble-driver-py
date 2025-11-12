# Installing pc-ble-driver-py

This guide explains how to install `pc-ble-driver-py` into your Python project.

## Quick Installation

The easiest way to install `pc-ble-driver-py` is using the provided installation script:

```bash
curl -O https://raw.githubusercontent.com/kimalive/pc-ble-driver-py/master/install_pc_ble_driver_py.sh
chmod +x install_pc_ble_driver_py.sh
./install_pc_ble_driver_py.sh
```

This script will:
- Install from source (ensures correct Python library linking)
- Automatically set up vcpkg if needed
- Install the `nrf-ble-driver` dependency
- Build and install `pc-ble-driver-py` into your current Python environment

## Installation Options

### Install Latest Version

```bash
./install_pc_ble_driver_py.sh
```

Installs the latest version from the GitHub fork (includes all fixes).

### Install Specific Version

```bash
./install_pc_ble_driver_py.sh --version 0.17.11
```

Installs a specific version from GitHub releases.

### Non-Interactive Mode

```bash
./install_pc_ble_driver_py.sh --non-interactive
```

Runs without prompts (useful for CI/CD or automated scripts).

## Installing in PyCharm

1. **Open your PyCharm project** and ensure your Python interpreter is configured.

2. **Open Terminal in PyCharm** (View → Tool Windows → Terminal)

3. **Download and run the installer:**
   ```bash
   curl -O https://raw.githubusercontent.com/kimalive/pc-ble-driver-py/master/install_pc_ble_driver_py.sh
   chmod +x install_pc_ble_driver_py.sh
   ./install_pc_ble_driver_py.sh
   ```

4. **Verify installation:**
   ```python
   import pc_ble_driver_py
   print(pc_ble_driver_py.__version__)
   ```

The package will be installed into your project's Python interpreter.

## Installing in Other IDEs

### VS Code

1. Open the integrated terminal (`` Ctrl+` `` or View → Terminal)
2. Ensure your Python interpreter is selected (bottom-right of VS Code)
3. Run the installation script as shown above

### Jupyter Notebook / JupyterLab

1. Open a terminal from Jupyter (File → New → Terminal)
2. Run the installation script
3. Restart your kernel to use the newly installed package

## Requirements

- **macOS** (ARM64 or Intel)
- **Python 3.8+**
- **Git** (for cloning vcpkg repository)
- **CMake** and **C++ compiler** (for building from source)

The installation script will automatically set up vcpkg if it's not already installed.

## What Gets Installed

- **vcpkg**: C++ package manager (installed to `$(brew --prefix)/vcpkg` or `/usr/local/vcpkg`)
- **nrf-ble-driver**: Nordic BLE driver library (installed via vcpkg)
- **pc-ble-driver-py**: Python bindings for the BLE driver

## Troubleshooting

### vcpkg Installation Issues

If the script cannot write to the preferred location, it will automatically fall back to `$HOME/.local/vcpkg`.

### Build Errors

Ensure you have:
- CMake installed: `brew install cmake` or download from [cmake.org](https://cmake.org)
- Xcode Command Line Tools: `xcode-select --install`

### Import Errors

If you get import errors after installation:
1. Verify your Python interpreter is the same one used for installation
2. Check that the package is installed: `pip list | grep pc-ble-driver-py`
3. Try reinstalling: `./install_pc_ble_driver_py.sh --non-interactive`

## Manual Installation (Advanced)

If you prefer to install manually or the script doesn't work for your setup:

1. **Set up vcpkg:**
   ```bash
   git clone https://github.com/Microsoft/vcpkg.git $(brew --prefix)/vcpkg
   cd $(brew --prefix)/vcpkg
   ./bootstrap-vcpkg.sh
   export VCPKG_ROOT=$(brew --prefix)/vcpkg
   export CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake
   ```

2. **Install nrf-ble-driver:**
   ```bash
   $VCPKG_ROOT/vcpkg install nrf-ble-driver --triplet arm64-osx  # or x64-osx for Intel
   ```

3. **Install pc-ble-driver-py:**
   ```bash
   pip install --no-binary :all: git+https://github.com/kimalive/pc-ble-driver-py.git@master
   ```

## Need Help?

If you encounter issues:
- Check that your Python environment is activated
- Verify all requirements are installed
- Ensure you have write permissions for vcpkg installation location

