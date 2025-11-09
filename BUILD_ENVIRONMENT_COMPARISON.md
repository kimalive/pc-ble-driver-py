# Build Environment Comparison: Local vs GitHub Actions

## Purpose

This document tracks differences between local build environment and GitHub Actions build environment that could cause the segfault issue in Python 3.9+ wheels.

## Known Issue

- **Local wheels**: All Python versions (3.8-3.13) work correctly
- **GitHub Actions release wheels**: 
  - ✅ Python 3.8: Works
  - ❌ Python 3.9-3.12: Segfault (exit code -11)
  - ❌ Python 3.13: SystemError (extension module initialization failed)

## Comparison Checklist

### System Environment
- [ ] macOS version
- [ ] macOS build version
- [ ] Kernel version
- [ ] Architecture

### Compiler Environment
- [ ] CC version
- [ ] CXX version
- [ ] Compiler flags (CFLAGS, CXXFLAGS)
- [ ] Linker flags (LDFLAGS)
- [ ] MACOSX_DEPLOYMENT_TARGET

### Python Environment
- [ ] Python installation method (pyenv vs actions/setup-python)
- [ ] Python build configuration
- [ ] Python library path
- [ ] Python framework vs non-framework
- [ ] Python prefix/base prefix

### Build Configuration
- [ ] CMake version
- [ ] CMake flags
- [ ] SWIG version
- [ ] VCPKG version and configuration
- [ ] Environment variables (VCPKG_ROOT, CMAKE_PREFIX_PATH, etc.)

### Build Artifacts
- [ ] .so file size
- [ ] .so file linking (otool -L)
- [ ] RPATH configuration
- [ ] Load commands
- [ ] Symbols

## How to Use

1. **Run local environment capture:**
   ```bash
   ./compare_build_environments.sh > local_build_env.log
   ```

2. **Compare with GitHub Actions logs:**
   - Check the "Build Environment Info" section in GitHub Actions build logs
   - Compare each section with local_build_env.log
   - Look for differences in:
     - MACOSX_DEPLOYMENT_TARGET
     - Compiler versions
     - Python build configuration
     - Environment variables

3. **Check build logs:**
   - Download build logs from GitHub Actions artifacts
   - Compare compiler flags and linker commands
   - Look for warnings or errors

## Potential Issues to Investigate

### 1. MACOSX_DEPLOYMENT_TARGET Mismatch
- **Symptom**: Wheels built with different deployment targets may not work on all systems
- **Check**: Compare `MACOSX_DEPLOYMENT_TARGET` between local and GitHub Actions
- **Fix**: Ensure both use the same deployment target

### 2. Compiler Version Differences
- **Symptom**: Different compiler versions may produce incompatible binaries
- **Check**: Compare `cc --version` and `c++ --version`
- **Fix**: Use same compiler version or ensure compatibility

### 3. Python Framework vs Non-Framework
- **Symptom**: Framework vs non-framework Python installations have different linking requirements
- **Check**: Compare `PYTHONFRAMEWORK` in Python build config
- **Fix**: Ensure consistent Python installation type

### 4. Missing Compiler Flags
- **Symptom**: Missing flags could cause ABI incompatibilities
- **Check**: Compare CFLAGS, CXXFLAGS, LDFLAGS
- **Fix**: Ensure all necessary flags are set

### 5. RPATH Configuration
- **Symptom**: Incorrect RPATH could cause library loading issues
- **Check**: Compare `otool -l` output for RPATH sections
- **Fix**: Ensure RPATH is correctly configured

## Next Steps

1. Run `compare_build_environments.sh` locally
2. Trigger GitHub Actions build and capture logs
3. Compare the outputs
4. Identify differences
5. Apply fixes to match local environment or fix GitHub Actions environment

