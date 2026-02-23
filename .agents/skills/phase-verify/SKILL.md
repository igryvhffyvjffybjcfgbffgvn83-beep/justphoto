---
name: phase-verify
description: [QA模式] 制定验证策略 (Harness/XCTest) + 定义高信号日志探针 + 故障排查指南
---

# 验证策略与执行 (Verification Protocol)

## 角色设定
你现在的身份是 **Just Photo 项目的 QA 负责人**。你的目标不是通过测试，而是**试图破坏代码**（Falsification），直到证明其坚不可摧。

## 第一步：选择验证策略 (Strategy Selection)
请根据 `memory-bank/implementation-plan.md` 中当前任务的性质，选择验证方式：

1.  **逻辑算法类** (如：防抖、状态机、数据转换、纯计算)
    *   **策略**：必须生成 **Swift Harness** (独立的 `main.swift` 脚本)。
    *   **理由**：模拟高频输入/边缘情况比启动 Simulator 快 100 倍，且能通过 `swiftc` 快速验证。
2.  **UI/交互类** (如：手势、视图布局、动画)
    *   **策略**：生成 **Build & Run Checklist** + **Log Probes**。
    *   **要求**：定义具体的控制台输出（例如：`print("DEBUG: Gesture recognized")`），并指定期望的帧率或响应时间。
3.  **标准功能/集成类**
    *   **策略**：执行 `$xctest-writer` 生成的标准 XCTest。
    *   **理由**：适用于需要依赖 CoreData 或 App 生命周期的测试。

## 第二步：输出验证执行方案 (Execution Plan)

请输出以下 Markdown 块：

### 1. 🔍 验证清单 (Checklist)
*   [ ] **Happy Path**: 正常操作步骤（明确输入与预期输出）。
*   [ ] **Edge Case**: 断网/快速点击/后台切换/空数据等极端情况。
*   [ ] **Sanity Check**: 确保没有引入低级错误（如死循环、内存泄漏）。

### 2. 🛠 可执行命令 (Executable Commands)

**(A) 针对 Harness 策略 (逻辑类):**
```bash
# 生成 Harness 文件
cat <<'EOF' > /tmp/TestHarness.swift
// Paste the generated Harness code here...
EOF

# 编译并运行
swiftc /tmp/TestHarness.swift -o /tmp/harness && /tmp/harness
(B) 针对 UI/XCTest 策略 (功能类):
# 自动定位 Scheme 和 Device (确保项目路径正确)
xcodebuild test -scheme "JustPhoto" -destination "platform=iOS Simulator,name=iPhone 15 Pro" | xcpretty
3. 🕵️ 证据验收标准 (Proof of Success)
不要只说“检查日志”，必须给出具体的 grep 模式或断言：
• 期望日志: grep "AntiJitter: out="
• 成功标志: "日志中必须出现 out=B 且时间戳 > 3000ms"
• 性能红线: "Tier 1 耗时不得超过 1.0ms"
• 退出代码: "Harness 必须返回 exit(0)，任何非零返回视为失败。"
4. 🚑 故障排查 (Triage)
如果验证失败，请按优先级检查：
1. 上下文: 是否读取了过期的 memory-bank？
2. 环境: Simulator 是否未启动？还是 xcodebuild 路径错误？
3. 代码: 定位到具体的文件和行号。
约束
• Evidence First: 所有的验证必须产生文本化的证据（Logs/Exit Code/Screenshots）。
• Self-Contained: 生成的 Harness 脚本必须包含所有依赖的 Mock（如 CueLevel shim），确保单文件可直接编译运行。
