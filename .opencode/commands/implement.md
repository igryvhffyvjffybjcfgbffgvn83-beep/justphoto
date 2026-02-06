请阅读 `/memory-bank` 下的所有文件，特别是 `implementation-plan.md` 和 `tech-stack.md`。

**任务目标：**
请执行 implementation-plan.md 中的 **$STEP**。

**执行要求：**
1.  **胶水编程 (Glue Coding) 优先**：
    *   **Think Harder**：这是一个复杂逻辑。请不要尝试自己从头构建算法。
    *   **搜索与复用**：利用你的知识库或 `sourcegraph` 工具，搜索 iOS/Swift 的标准实现模式（Pattern）或成熟开源库。
    *   **集成策略**：如果需要引入第三方库，请明确告诉我库的名称、GitHub 地址，以及如何通过 **Swift Package Manager (SPM)** 集成它。
2.  **思路先行**：在写代码前，先简述你的技术方案（是复用原生 API，还是引入库？），列出打算修改的文件。
3.  **编写代码**：确认方案后，执行必要的终端命令（`touch`, `mkdir`）和代码写入（`write`）。
4.  **验证方法**：代码写完后，请明确告诉我如何验证这一步是否成功（例如：‘运行项目，控制台应输出 Camera Initialized的每一个详细步骤’），并且跟我说一句 **$STEP**请查收。

**严格限制：**
在我告诉我‘验证通过’之前，**绝对不要**进行 **$STEP** 的下一步
