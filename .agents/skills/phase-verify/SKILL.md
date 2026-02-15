---
name: phase-verify
description: 生成验证清单 + 运行命令 + 探针/日志验证点 + 失败时定位路径
---

# 分阶段验证规范

## 目标
生成可执行的验证清单与命令，明确日志/探针验收点，并给出失败时定位路径。

## 输出要求
1. **Verification Checklist**（逐条可执行）
2. **CLI Commands**（xcodebuild / 日志探针）
3. **Expected Evidence**（关键日志/探针输出）
4. **Failure Triage**（失败时优先排查路径）
5. **Assumptions**（缺信息时的最安全默认假设）

## 约束
- 命令必须可复制执行。
- 如果需要设备名，先提示使用 `xcrun simctl list devices available`。
