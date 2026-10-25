#!/usr/bin/env python3
"""生成 CI 缺失的私有/第三方框架 tbd 桩。

iOS SDK 与 Theos vendor 都不带 Preferences 这类私有框架的链接桩，
但头文件是有的（Theos vendor/headers）。按头文件里的 @interface 生成最小 tbd 即可。
"""
import os
import re
import sys

FRAMEWORKS = {
    "Preferences": "/opt/theos/vendor/include/Preferences",
}


def collect_classes(header_dir):
    classes = set()
    if not os.path.isdir(header_dir):
        return []
    for name in sorted(os.listdir(header_dir)):
        if not name.endswith(".h"):
            continue
        try:
            text = open(os.path.join(header_dir, name), errors="ignore").read()
        except OSError:
            continue
        for m in re.finditer(r"@interface\s+([A-Za-z_]\w*)", text):
            classes.add(m.group(1))
    return sorted(classes)


def build_tbd(framework, classes):
    install_name = f"/System/Library/PrivateFrameworks/{framework}.framework/{framework}"
    joined = ", ".join(classes)
    return (
        "--- !tapi-tbd\n"
        "tbd-version:     4\n"
        "targets:         [ arm64e-ios ]\n"
        "flags:           [ not_app_extension_safe ]\n"
        f"install-name:    '{install_name}'\n"
        "current-version: 1.0.0\n"
        "compatibility-version: 1.0.0\n"
        "exports:\n"
        "  - targets:         [ arm64e-ios ]\n"
        f"    objc-classes:    [ {joined} ]\n"
        "...\n"
    )


def main():
    out_root = sys.argv[1] if len(sys.argv) > 1 else "/opt/theos/vendor/lib/iphone/roothide"
    hdr_root = sys.argv[2] if len(sys.argv) > 2 else "/opt/theos/vendor/include"
    failures = 0

    for framework in FRAMEWORKS:
        header_dir = os.path.join(hdr_root, framework)
        classes = collect_classes(header_dir)
        if not classes:
            print(f"[{framework}] no @interface found under {header_dir}", file=sys.stderr)
            failures += 1
            continue

        fw_dir = os.path.join(out_root, f"{framework}.framework")
        os.makedirs(fw_dir, exist_ok=True)
        path = os.path.join(fw_dir, f"{framework}.tbd")
        with open(path, "w") as f:
            f.write(build_tbd(framework, classes))
        print(f"[{framework}] {path}  ({len(classes)} classes)")
        print(f"           {', '.join(classes)}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
