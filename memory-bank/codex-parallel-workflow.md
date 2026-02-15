# Codex 并行智能体工作流（Just Photo）

## 目标
将串行闭环「拆解 → 分阶段实现 → 验证 → 存档」升级为 3~5 线程并行协作，并保持最小改动与可审计日志。

## Worktree 并行实践（3~5 线程）
以下步骤以 Codex App + Git worktree 为基础（每个线程一个 worktree）：

1. 在主仓库创建并行 worktree（每个线程独立分支）。
2. 在 Codex App 中分别打开每个 worktree。
3. Planner 先产出任务拆解与阶段边界（单一事实源）。
4. Implementer A/B 分别实现被分配的阶段。
5. Tester worktree 负责拉取/合并变更并执行验证。
6. Archivist worktree 负责归档与 `memory-bank/` 更新。

## 线程分工模板（每线程一句话）
- **Planner**：只负责拆解阶段、风险与验收点；不写业务代码。
- **Implementer A**：只负责阶段 A 的最小改动实现；不修改验证或归档文档。
- **Implementer B**：只负责阶段 B 的最小改动实现；不跨阶段扩展需求。
- **Tester**：只负责验证清单、命令执行与日志证据；不改业务逻辑。
- **Archivist**：只负责变更记录/Changelog/PR 草稿与 `memory-bank/` 归档；不改功能代码。

## 仅能本地验证一次时的同步策略
当你只能在本地跑一次真机/模拟器验证：

1. 每个 Implementer 在各自 worktree 完成后提交 commit。
2. 在 Tester worktree 里 `git fetch` 并 `git cherry-pick` 需要验证的 commits。
3. Tester 统一跑一次验证（Xcode / xcodebuild / 日志探针）。
4. 验证通过后，将合并结果回主分支或提交一个汇总分支。
5. Archivist 在主分支（或汇总分支）更新 `memory-bank/` 归档。

## 最短路径操作（6~10 步）
1. Planner 输出「拆解 + 依赖 + 验收点」计划。
2. Implementer A/B 领取对应阶段并各自实现最小改动。
3. Implementer A/B 各自自检并提交 commit。
4. Tester worktree 拉取并 cherry-pick 实现 commits。
5. Tester 运行验证命令并确认日志/探针证据。
6. 若失败，回传具体失败点与定位路径。
7. 通过后，合并到主分支或汇总分支。
8. Archivist 更新 `memory-bank/` 与 Changelog/PR 草稿。
