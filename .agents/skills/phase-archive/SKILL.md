---
name: phase-archive
description: 变更记录/归档/Changelog 草稿/PR 描述草稿（默认写入 memory-bank/）
---

请阅读 `/memory-bank` 下的所有文件。

**任务：更新项目记忆库并进行版本存档 (Step: $STEP)。**

请严格按照顺序执行以下 3 个动作：

1.  **更新文档 (Update Docs)**：
    *   编辑 `memory-bank/progress.md`，将 **$STEP** 标记为 `[x]` 已完成。
    *   如果 **$STEP** 涉及了新文件或架构调整，请同步更新 `memory-bank/architecture.md`。

2.  **Git 存档 (Git Commit)**：
    *   使用 `bash` 工具执行命令：`git add .`
    *   使用 `bash` 工具执行命令：`git commit -m "feat: Complete $STEP"`
    *   *(可选)* 如果需要，执行 `git push`。

3.  **验证 (Verify)**：
    *   确认文档已更新且 Git 工作区已干净 (Working tree clean)。

最后告诉我：“✅ 记忆库已更新，代码已存档 (Commit ID: xxx)。