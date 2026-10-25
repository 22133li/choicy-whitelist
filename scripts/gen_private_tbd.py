#!/usr/bin/env python3
"""生成 CI 缺失的私有框架 tbd 桩。

iOS SDK 与 Theos vendor 都不带 Preferences 这类私有框架的链接桩，
但头文件是有的（Theos vendor/headers）。按头文件里的 @interface 与 ivar 生成最小 tbd。

注意：tbd 必须同时导出
  - objc-classes / objc-eh-types（类本身）
  - objc-ivars（每个类的实例变量，符号名是 _OBJC_IVAR_$_<Class>.<ivar>）
否则 ld 会报 Undefined symbols。
"""
import os
import re
import sys

FRAMEWORKS = {
    "Preferences": "/opt/theos/vendor/include/Preferences",
}

# 头文件里没有、但 ChoicyPrefs 实际引用了的类
EXTRA_CLASSES = {
    "Preferences": ["PSEditableListController"],
}

INTERFACE_RE = re.compile(r"@interface\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_]\w*))?[^\n{]*\{", re.S)


def collect(header_dir, extra_classes):
    """返回 (classes, ivars)  classes: set；ivars: dict[Class] -> set[ivar]"""
    classes = set(extra_classes)
    ivars = {}

    if not os.path.isdir(header_dir):
        return classes, ivars

    for name in sorted(os.listdir(header_dir)):
        if not name.endswith(".h"):
            continue
        try:
            text = open(os.path.join(header_dir, name), errors="ignore").read()
        except OSError:
            continue

        # 单行 @interface Foo : Bar 形式
        for m in re.finditer(r"@interface\s+([A-Za-z_]\w*)", text):
            classes.add(m.group(1))

        # 带 ivar 块的 @interface Foo : Bar { ... }
        for m in INTERFACE_RE.finditer(text):
            cls = m.group(1)
            brace_start = text.find("{", m.start())
            depth = 0
            i = brace_start
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            block = text[brace_start + 1 : i]
            found = set()
            for line in block.split(";"):
                line = line.strip()
                if not line or line.startswith("//") or line.startswith("/*"):
                    continue
                for var in re.finditer(r"\b([A-Za-z_]\w*)\s*(?=\[|$)", line.strip()):
                    v = var.group(1)
                    if v not in ("IBOutlet", "nonatomic", "strong", "weak", "retain",
                                 "assign", "copy", "readonly", "readwrite", "atomic"):
                        found.add(v)
            if found:
                ivars.setdefault(cls, set()).update(found)

    return classes, ivars


def build_tbd(framework, classes, ivars):
    install_name = f"/System/Library/PrivateFrameworks/{framework}.framework/{framework}"
    lines = [
        "--- !tapi-tbd",
        "tbd-version:     4",
        "targets:         [ arm64e-ios ]",
        "flags:           [ not_app_extension_safe ]",
        f"install-name:    '{install_name}'",
        "current-version: 1.0.0",
        "compatibility-version: 1.0.0",
        "exports:",
        "  - targets:         [ arm64e-ios ]",
        f"    objc-classes:    [ {', '.join(sorted(classes))} ]",
    ]
    ivar_syms = sorted(
        f"{cls}.{iv}" for cls, vs in ivars.items() for iv in vs
    )
    if ivar_syms:
        lines.append(f"    objc-ivars:      [ {', '.join(ivar_syms)} ]")
    lines.append("...")
    return "\n".join(lines) + "\n"


def main():
    out_root = sys.argv[1] if len(sys.argv) > 1 else "/opt/theos/vendor/lib/iphone/roothide"
    hdr_root = sys.argv[2] if len(sys.argv) > 2 else "/opt/theos/vendor/include"
    failures = 0

    for framework in FRAMEWORKS:
        header_dir = os.path.join(hdr_root, framework)
        classes, ivars = collect(header_dir, EXTRA_CLASSES.get(framework, []))
        if not classes:
            print(f"[{framework}] nothing found under {header_dir}", file=sys.stderr)
            failures += 1
            continue

        fw_dir = os.path.join(out_root, f"{framework}.framework")
        os.makedirs(fw_dir, exist_ok=True)
        path = os.path.join(fw_dir, f"{framework}.tbd")
        with open(path, "w") as f:
            f.write(build_tbd(framework, classes, ivars))
        print(f"[{framework}] {path}")
        print(f"    classes({len(classes)}): {', '.join(sorted(classes))}")
        print(f"    ivars: {sum(len(v) for v in ivars.values())}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
