# Command: project:breakdown
# Description: [Vibe] 智能拆解：风险审计 + 动态分期 (2-4步) + 验证闭环

<!-- 1. 自动加载核心上下文 -->
READ memory-bank/product-requirement.md
READ memory-bank/architecture.md
READ memory-bank/implementation-plan.md

Prompt:
我现在准备执行任务：**$TASK_NAME**。
相关的具体文档/代码是：**$RELATED_FILES** (如果没有可填无)

请作为 **Just Photo 项目的资深 iOS 架构师**，执行以下 **“任务预演 (Pre-flight Check)”**：

### 1. 风险审计 (Risk Audit)
请作为**防御性架构师**分析以下风险（不要只看 Happy Path）：
*   **竞态与并发**：是否存在跨线程访问、死锁或异步时序依赖？
*   **状态一致性**：是否存在非法中间态（如数据已删但 UI 还在）？
*   **生命周期**：如果操作被中断、重置或 App 被杀，数据是否安全？

### 2. 动态分期策略 (Dynamic Phasing)
为了确保**逻辑零漏洞**且**易于调试**，请根据任务的复杂度，将其拆分为 **2 到 4 个原子阶段 (Atomic Phases)**。

**拆分原则（必须遵守）：**
1.  **Phase 1 永远是 [纯逻辑/内核层]**：只写 Struct/Class/算法，不写 UI，不写 DB，不写胶水代码。必须能通过 Mock 数据验证。
2.  **后续阶段**根据需要安排：
    *   如果是数据任务 -> Phase 2 负责持久化 (DB/File)。
    *   如果是 UI 任务 -> Phase X 负责 View 实现。
    *   最后阶段负责 **集成与胶水代码** (Wiring)。

### 3. 输出执行计划书 (Output Requirements)
请输出一份 Markdown 计划书，包含：
1.  **数据结构预览**：核心 `struct/enum` 定义。
2.  **分阶段验证指令**：
    *   Phase 1: "运行代码，控制台应输出 `[DEBUG] Logic: ...`"
    *   Phase N: "真机操作... 控制台应输出 `[DEBUG] Final: ...`"

**注意：请根据实际情况决定阶段数量（2-4个）。现在不要写代码，只输出计划。**