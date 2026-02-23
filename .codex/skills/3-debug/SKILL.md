# Command: project:debug
# Description: [Vibe] 智能诊断与修复：定位 -> 分析 -> 方案 -> 验证

<!-- 读取关键架构，防止修复方案破坏现有规则 -->
READ memory-bank/architecture.md
READ memory-bank/tech-stack.md

Prompt:
我遇到了以下 **错误信息** 或 **异常现象**：
$ERROR_OR_ISSUE

请作为 **Just Photo 项目的资深 iOS 架构师**，执行以下修复流程：

### 1. 定位与分析 (Locate & Analyze)
*   **定位**：明确指出是哪个文件、哪行代码出的问题。
*   **归因**：解释根本原因（是逻辑漏洞？线程安全问题？还是 PoseSpec 约束冲突？）。

### 2. 修复方案 (Solution)
请提出 **2-3 种修复方案**，并推荐最符合 "Local-only" 和 "Glue Coding" 原则的方案。
*   **注意**：如果是 `write_failed` 或 `permission` 相关问题，必须遵循 `architecture.md` 中的状态机定义。

### 3. 执行与验证 (Execute & Verify)
*   **代码实现**：请输出修复后的代码（使用 `write` 或 `edit`）。
*   **验证闭环**：
    *   **DebugTools 增强**：如果问题难以复现，请在 `DebugToolsScreen.swift` 中添加一个专门的 **测试按钮**（例如 `TestFixFor...`），点击后能模拟触发该边缘情况并打印 Console Log。
    *   **预期日志**：告诉我修复后，控制台/ui界面应该输出什么样的日志才算成功。
