---
name: task-breakdown
description: 拆解 + 分阶段 + 风险 + 验收点（仅输出计划，不写代码）
---

# 任务拆解规范

## 目标
只做任务拆解与风险审计，不写代码、不修改文件。

## 必须读取的上下文
- `memory-bank/product-requirement.md`
- `memory-bank/architecture.md`
- `memory-bank/implementation-plan.md`

## 输出要求
1. **阶段边界 + 依赖关系**（2~4 个阶段）
2. **风险审计**（并发/状态一致性/生命周期）
3. **每阶段验收点**（可执行、可观测）
4. **验证方式**（Xcode / xcodebuild / 日志探针）
5. **Assumptions**（缺信息时的最安全默认假设）

## 约束
- 只输出计划，不写实现细节。
- 阶段划分以最小可验证单元为准。
