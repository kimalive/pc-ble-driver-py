#!/usr/bin/env python3
import sys
import os
import sysconfig
import re

def main() -> int:
    pure = sysconfig.get_paths().get("purelib") or ""
    path = os.path.join(pure, "skbuild", "constants.py")
    print(f"[patch_skbuild] constants.py: {path} {'(exists)' if os.path.isfile(path) else '(missing)'}")
    if not os.path.isfile(path):
        return 0
    try:
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
        # Preserve indentation of the matched line
        pattern = r'^([ \t]*)major_macos,\s*minor_macos\s*=\s*release\.split\("."\)\[:2\]\s*$'
        m = re.search(pattern, src, flags=re.MULTILINE)
        if m:
            indent = m.group(1)
            replacement = (
                f'{indent}parts = release.split(".")\n'
                f'{indent}if len(parts) < 2:\n'
                f'{indent}    release = f"{{parts[0]}}.0" if parts else "15.0"\n'
                f'{indent}major_macos, minor_macos = release.split(".")[:2]\n'
            )
            dst = re.sub(pattern, replacement, src, count=1, flags=re.MULTILINE)
            if dst != src:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(dst)
                print("[patch_skbuild] ✓ Patched constants.py (indent preserved)")
            else:
                print("[patch_skbuild] constants.py unchanged (regex no-op)")
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


