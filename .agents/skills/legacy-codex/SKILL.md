---
name: legacy-codex
description: 兼容旧版 .codex/skills 的综合指令集（仅用于过渡）
---

# Legacy Codex Compatibility Skill

该 skill 用于保留旧的 `.codex/skills` 指令精神，作为过渡兼容层。
默认仍应优先使用新的标准 skills（如 `task-breakdown`, `phase-implement`, `phase-verify`, `phase-archive`, `xctest-writer`）。

## 指令精神（摘要）
- **Breakdown**：执行任务预演，做风险审计 + 动态分期 + 验证闭环（只输出计划）。
- **Implement (Glue Coding)**：胶水编程优先，最小改动，虚拟编译检查，输出可验证的结果。
- **Debug**：定位 → 分析 → 方案 → 验证，必要时补充可触发的调试入口与日志。
- **Review**：安全性、命名、架构一致性、冗余检查。
- **Test**：为新/改动的 Swift 文件补充 XCTest，覆盖 happy path 与 edge cases。
- **Memo/Archive**：更新 `memory-bank/` 进度与归档记录。

> 备注：该 skill 仅做兼容，不作为默认推荐入口。
