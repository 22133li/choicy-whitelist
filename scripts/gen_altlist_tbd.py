#!/usr/bin/env python3
"""从 AltList 头文件生成最小 tbd 桩。

ChoicyPrefs 编译期只需要 AltList 的 ObjC 类符号，不需要真实 framework 实现。
AltList 本体链接依赖 Preferences 私有框架，CI 上没有，故用 tbd 绕过。
"""
import os
import sys

hdr_dir = sys.argv[1] if len(sys.argv) > 1 else \
    "/opt/theos/vendor/lib/iphone/roothide/AltList.framework/Headers"
out = os.path.join(os.path.dirname(hdr_dir), "AltList.tbd")

if not os.path.isdir(hdr_dir):
    print("headers dir missing:", hdr_dir)
    sys.exit(1)

names = [f[:-2] for f in os.listdir(hdr_dir) if f.endswith(".h")]
# 只取 ObjC 类；"X+AltList" 是分类(category)，不能出现在 objc-classes 段
classes = sorted({n for n in names if n.startswith("ATL") and "+" not in n})
if not classes:
    print("no AltList classes found in", hdr_dir)
    sys.exit(1)

tbd = f"""--- !tapi-tbd
tbd-version:     4
targets:         [ arm64e-ios ]
flags:           [ not_app_extension_safe ]
install-name:    '@rpath/AltList.framework/AltList'
current-version: 1.0.0
compatibility-version: 1.0.0
exports:
  - targets:         [ arm64e-ios ]
    objc-classes:    [ {", ".join(classes)} ]
...
"""
with open(out, "w") as f:
    f.write(tbd)

print(f"wrote {out} with {len(classes)} classes")
for c in classes:
    print("  -", c)
