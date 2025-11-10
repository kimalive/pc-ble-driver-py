#!/usr/bin/env python3
import sys
import os
import sysconfig

def main() -> int:
    pure = sysconfig.get_paths().get("purelib") or ""
    path = os.path.join(pure, "skbuild", "constants.py")
    print(f"[patch_skbuild] constants.py: {path} {'(exists)' if os.path.isfile(path) else '(missing)'}")
    if not os.path.isfile(path):
        return 0
    try:
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
        needle = 'major_macos, minor_macos = release.split(".")[:2]'
        replacement = (
            'parts = release.split(".")\n'
            'if len(parts) < 2:\n'
            '    release = f"{parts[0]}.0" if parts else "15.0"\n'
            'major_macos, minor_macos = release.split(".")[:2]'
        )
        if needle in src:
            dst = src.replace(needle, replacement)
            if dst != src:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(dst)
                print("[patch_skbuild] ✓ Patched constants.py")
            else:
                print("[patch_skbuild] constants.py unchanged (identical after replace)")
        else:
            print("[patch_skbuild] Pattern not found; no change made")
        # show head for diagnostics
        with open(path, "r", encoding="utf-8") as f:
            head = "".join(list(f.readlines()[:30]))
        print("[patch_skbuild] --- head ---\n" + head)
    except Exception as e:
        print(f"[patch_skbuild] Error: {e}")
        return 0
    return 0

if __name__ == "__main__":
    sys.exit(main())


