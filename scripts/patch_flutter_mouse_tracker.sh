#!/bin/bash
# 修复 Flutter macOS 上「点击卡死 / 点不动」的根因：
# MouseTracker._deviceUpdatePhase 的防重入断言在 macOS 上会因鼠标 hover
# 触发合法重入而崩溃（flutter/flutter#126954 等）。release 模式无此断言，
# 此 patch 让 debug 模式行为与 release 一致：用深度计数允许重入。
#
# 用法：flutter upgrade 之后执行一次：bash scripts/patch_flutter_mouse_tracker.sh
set -euo pipefail

FLUTTER_ROOT="${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}"
if [ -z "${FLUTTER_ROOT:-}" ]; then
  echo "找不到 flutter，请设置 FLUTTER_ROOT 环境变量" >&2
  exit 1
fi

FILE="$FLUTTER_ROOT/packages/flutter/lib/src/rendering/mouse_tracker.dart"

# 已打过补丁则跳过
if grep -q '_deviceUpdateDepth' "$FILE"; then
  echo "已打过补丁，跳过。"
  exit 0
fi

python3 - "$FILE" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r") as f:
    src = f.read()

old = """  bool _debugDuringDeviceUpdate = false;
  // Used to wrap any procedure that might call `_handleDeviceUpdate`.
  //
  // In debug mode, this method uses `_debugDuringDeviceUpdate` to prevent
  // `_deviceUpdatePhase` being recursively called.
  void _deviceUpdatePhase(VoidCallback task) {
    assert(!_debugDuringDeviceUpdate);
    assert(() {
      _debugDuringDeviceUpdate = true;
      return true;
    }());
    task();
    assert(() {
      _debugDuringDeviceUpdate = false;
      return true;
    }());
  }"""

new = """  int _deviceUpdateDepth = 0;
  // Used to wrap any procedure that might call `_handleDeviceUpdate`.
  //
  // In debug mode, this method uses `_deviceUpdateDepth` to allow
  // `_deviceUpdatePhase` to be called reentrantly (which happens on macOS
  // when hover callbacks rebuild the tree during pointer dispatch).
  void _deviceUpdatePhase(VoidCallback task) {
    _deviceUpdateDepth += 1;
    task();
    _deviceUpdateDepth -= 1;
  }"""

if old not in src:
    print("未找到预期的代码块，请检查 Flutter 版本。")
    sys.exit(1)

src = src.replace(old, new)
src = src.replace("    assert(_debugDuringDeviceUpdate);", "    assert(_deviceUpdateDepth > 0);")

with open(path, "w") as f:
    f.write(src)

print("已打补丁：mouse_tracker.dart 允许重入，不再崩溃。")
PY
