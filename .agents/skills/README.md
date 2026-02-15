# Skills 目录说明

本仓库优先使用标准化 skills 目录：
- `.agents/skills/<skill-name>/SKILL.md`（每个 skill 独立文件夹）
- 每个 skill 目录包含 `agents/openai.yaml`，且 `allow_implicit_invocation=false`，要求显式用 `$skill` 调用

## 兼容层
为兼容旧的 `.codex/skills`（保留不改动），提供一个包装 skill：
- 兼容入口：`.agents/skills/SKILL.md`
- 实体位置：`.agents/skills/legacy-codex/SKILL.md`

**说明**：`.agents/skills/SKILL.md` 是一个软链接，指向 `legacy-codex` 的标准 skill 文件。
未来新增/维护请以 `.agents/skills/` 为准，`.codex/skills` 仅作历史兼容。
