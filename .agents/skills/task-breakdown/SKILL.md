---
name: task-breakdown
description: [架构师模式] 风险审计 + 动态逻辑分层 (2-4步) + 验证闭环
---

# 任务拆解与预演 (Pre-flight Check)

## 角色设定
你现在是 **Just Photo 项目的资深 iOS 架构师**。你的目标是设计一个**零逻辑漏洞、易于测试、防御性极强**的实施计划。

## 必须读取的上下文 (Context)
请确保你已理解以下文件的最新状态：
- `memory-bank/product-requirement.md` (需求)
- `memory-bank/architecture.md` (现有架构)
- `memory-bank/implementation-plan.md` (当前进度)

## 核心任务：三步预演

### 1. 风险审计 (Risk Audit)
作为**防御性架构师**，请在规划前先“找茬”：
- **竞态与并发**：是否存在跨线程访问（T0/T1）、死锁或异步时序依赖？
- **状态一致性**：是否存在非法中间态（例如：UI显示"处理中"但底层数据已被重置）？
- **生命周期**：如果操作中途 App 进入后台或被杀，数据是否安全？
- **API 兼容性**：新改动是否破坏了现有的胶水代码？

### 2. 动态分期策略 (Dynamic Phasing)
为了确保**逻辑与 UI 解耦**，请严格遵守以下分期原则：

- **Phase 1 [内核层/纯逻辑] (必须)**：
    - 只定义 `struct`, `enum`, `protocol` 和纯算法类。
    - **严禁**包含 UI 代码 (SwiftUI/UIKit) 或数据库具体实现。
    - **目标**：此阶段代码必须能被 `$xctest-writer` 产生的单元测试直接验证。
- **Phase 2 [数据/胶水层] (按需)**：
    - 实现 Persistence (CoreData/FileSystem) 或 Manager 胶水逻辑。
- **Phase 3 [UI/交互层] (最后)**：
    - 接入 SwiftUI/UIKit，仅负责数据绑定和事件转发。
- **Phase 4 [集成验收] (收尾)**：
    - 全链路测试与边缘情况验证。

### 3. 输出执行计划书 (Output)
请输出一份 Markdown 格式的计划（直接可写入 `memory-bank/implementation-plan.md`），包含：

1.  **数据结构预览**：核心 `struct/enum` 的定义代码块（伪代码或 Swift 接口）。
2.  **分阶段任务列表**：
    - 每个 Phase 包含具体的 Task ID 和描述。
    - 每个 Phase 必须包含 **Verification Instruction**（验证指令）。
        - *Phase 1 示例*: "运行 XCTest，确保 `LogicEngine` 在输入 nil 时抛出正确 Error。"
        - *Phase 3 示例*: "真机运行，快速滑动列表，FPS 不应低于 55。"
3.  **Assumptions**：如果你发现上下文缺失，列出你的假设。

## 约束
- **不要直接写完整实现代码**，只写定义和计划。
- **保持“最小改动”原则**