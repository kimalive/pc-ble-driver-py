# Build Environment Standardization

## Problem

Local builds work, but GitHub Actions builds fail or produce different results, even though both use virtual environments. This is because:

1. **System-level tools differ**: CMake, SWIG, compiler versions may differ
2. **Python installation methods differ**: pyenv vs actions/setup-python
3. **macOS versions differ**: Local macOS 26.1 vs GitHub Actions macOS 15.7
4. **Environment variables differ**: Different defaults, paths, etc.
5. **Build tool versions differ**: pip, setuptools, scikit-build versions

## Solution: Standardized Build Environment Script

We've created `setup_build_environment.sh` that:
- ✅ Installs/verifies specific versions of build tools
- ✅ Sets consistent environment variables
- ✅ Handles both local and CI environments
- ✅ Verifies all dependencies are present
- ✅ Fixes known issues (e.g., scikit-build macOS version parsing)

## Usage

### Local Builds

```bash
# Source the script to set up environment
source ./setup_build_environment.sh

# Then build as usual
./build_wheels.sh
```

### GitHub Actions

The workflow should call this script before building:

```yaml
- name: Setup build environment
  run: ./setup_build_environment.sh

- name: Build wheel
  run: |
    # Build commands here
```

## Alternative: Use cibuildwheel

For even better consistency, consider using [cibuildwheel](https://github.com/pypa/cibuildwheel):

```yaml
- name: Build wheels
  uses: pypa/cibuildwheel@v2.16.2
  env:
    CIBW_BEFORE_BUILD: ./setup_build_environment.sh
    CIBW_MANYLINUX_X86_64_IMAGE: manylinux2014
```

## Benefits

1. **Identical environments**: Same tool versions, same environment variables
2. **Reproducible builds**: Same inputs = same outputs
3. **Easier debugging**: Can run exact same setup locally
4. **Version pinning**: Prevents "works on my machine" issues

## Next Steps

1. Update `build_wheels.sh` to source `setup_build_environment.sh`
2. Update GitHub Actions workflow to use `setup_build_environment.sh`
3. Consider pinning exact versions in a `requirements-build.txt`
4. Consider using Docker for even more isolation

