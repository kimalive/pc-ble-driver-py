import platform

_orig_release = getattr(platform, "release", None)

def _patched_release():
    try:
        rel = _orig_release() if _orig_release else ""
        return rel if "." in rel else (f"{rel}.0" if rel else "15.0")
    except Exception:
        return "15.0"

if callable(_orig_release):
    try:
        platform.release = _patched_release  # type: ignore[attr-defined]
    except Exception:
        pass


