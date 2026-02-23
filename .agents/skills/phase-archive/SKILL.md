---
name: phase-archive
description: [收尾模式] 清理临时文件 + 注入验证证据 + 更新记忆库 + Git 提交
---

# Role: Vibe Archivist (The Closer)

## 核心任务
将当前的开发成果固化为永久资产。
你不仅仅是提交代码，更是要为代码的健壮性留下永久的**数字指纹（Digital Fingerprint）**。

## 必须读取的上下文
- `memory-bank/progress.md`
- `memory-bank/activeContext.md` (如有)

---

# 执行协议 (Strict Protocol)

## 1. 🧹 清理战场 (Cleanup)
在提交前，务必删除 `phase-verify` 阶段产生的临时垃圾：
- 删除临时 Harness 文件（如 `/tmp/TestHarness.swift` 或项目根目录下的临时 `.swift`）。
- 删除临时编译产物（如 `harness` 可执行文件）。
- **执行**: `git clean -fd` (慎用，或手动删除指定文件) 确保工作区只包含源代码。

## 2. 📝 更新记忆库 (Memory Bank Update)
- **Architecture**: 如果 `$STEP` 修改了核心逻辑（如新增了 AntiJitterGate），在 `memory-bank/architecture.md` 中简要补充其职责。
- **Progress**: 在 `memory-bank/progress.md` 中：
    1. 将对应 Task 标记为 `[x]`。
    2. **关键步骤**：在 Task 下方添加 `> Evidence:` 引用块，简述验证结果（例如："Verified with Harness: T0 hold 3000ms passed, T1 cost 0.89ms"）。

## 3. 📦 提交与推送 (Commit & Push)
生成符合 Conventional Commits 规范的提交信息：
- **Header**: `feat/fix: <简短描述>`
- **Body**: 
    - 详细描述改动内容。
    - **必须包含**：`Verification: <验证手段>` (如 "Verified via Swift Harness" 或 "Passes XCTest")。
- **Action**:
    - `git add .`
    - `git commit -m "..."`
    - `git push`

---

# 结束语
✅ **归档完成**。
- Commit ID: [hash]
- 状态: 记忆库已同步，验证证据已固化。
- 下一步: 请指挥官指示下一个 `$STEP` 或结束会话。