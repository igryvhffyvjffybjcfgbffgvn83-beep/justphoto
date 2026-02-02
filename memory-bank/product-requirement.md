# ✅ PRD：Just Photo（iOS｜MVP｜合并版 v1.1.4）

- **日期**：2026-01-29
- **平台**：iOS 16+
- **合并来源**：
  - `product-requirement_v1.1.md`（产品机制 / MVP 冻结）
  - `prd (1).md`（Prototype-aligned 的 IA / UI / Epic / QA / 文案 / 埋点结构）
- **合并原则**：两份文档所有不一致处，均已按**番茄拍板**在本文写为最终口径；本文为开发与验收唯一依据。

---

### 0.0 版本信息与变更记录（冻结）

* **当前版本**：v1.1.4（在 v1.1.3 基础上合并 DT 补丁并继续冻结 P0 条款）
* **发布日期**：2026-01-29
* **唯一事实源**：本文件（若实现/讨论与本文冲突，以本文件“冻结”条款为准）
* **变更记录（冻结：必须维护；按版本倒序）**：

  - **v1.1.4｜2026-01-29｜DT 补丁（本次变更）**
    1) PoseSpec：`FRAME_GENERAL` Priority 降为 1（全局兜底仅作最后 fallback，不压制具体构图指令）
    2) withRef：`Match（达标）= PoseSpec exit`（统一口径，禁止另写硬编码阈值；新增 `match_blocked_by` 诊断）
    3) Photo write：`write_success` 后增加 **Asset Fetch Verification Retry**（500ms×1，避免 PhotoKit 索引延迟误报失败）
    4) Limited Access：补齐“已授权但不可读/已删除”自愈兜底（记录 `phantom_asset_detected`）
    5) ODR：`failed_retry` 状态增加网络恢复自动重试（NWPathMonitor；debounce=500ms；每次恢复最多 1 次）
    6) 可访问性澄清：PRD 的 `VoiceOver` 明确指 iOS 无障碍（冻结：MVP 不接入 App 内置 TTS）
    7) PoseSpec antiJitter：新增退出后冷却 `cooldownMs`（避免 cue 闪烁）
    8) 新增 Appendix A.13：本地诊断日志格式（明确 keys/字段/验收）

  - **v1.1.3｜2026-01-29｜P0 冻结版（基线）**
    - 在 v1.1.2 patched 基础上合并并冻结 P0 条款（相机权限/Session 20/写入失败阻断等）。

* **本次冻结范围（P0）**：

  1. 版本/Changelog 一致性
  2. 相机权限状态机 + 初始化失败分因
  3. Session 20 上限时快门/保存/可见性
  4. capture_failed 的 UI/计数/重试
  5. 并发拍摄与 write_failed 全局阻断策略
  6. thumb_failed 的自愈与永久失败口径
  7. album_add_failed 的修复入口与重试策略
  8. 提示等级表（L1/L2/L3）从 TODO 变为合同
  9. 夸夸 overlay 的按钮语义（👍/👎/展开/安静）
  10. 前后摄像头翻转的行为与状态继承
  11. Wrap/拼图页面级冻结规格与失败态
  12. withRef Match 口径=PoseSpec exit（禁止另写阈值）
  13. write_success 后 Asset Fetch Verification Retry（避免误报失败）
  14. PoseSpec antiJitter cooldownMs（退出后冷却，避免闪烁）
  15. ODR failed_retry 网络恢复自动重试
  16. Limited 权限 phantom_asset_detected 记录（已授权但不可读/已删除）
  17. 本地诊断日志格式（Appendix A.13｜keys/字段/导出）

---

## 0. 核心原则（必须遵守）

- **3 秒看懂，立刻能拍**（摄影师口吻、可执行；不解释、不术语、不评分）
- **先拍 → 再选 → 继续拍**（心流优先）
- **Data Safety**：照片必须写入系统相册（即拍即存；**写入失败=强提醒且阻断快门直至处理**；归档失败不阻断但提示修复；不允许 silent failure）
- **原片纯净**：不对原片加水印；品牌只出现在订阅/设置等非照片内容层
- **数据策略（冻结）**：仅本地统计/日志；不做事件/画像/性能上报；不建账号；不上传照片
- **本地日志（冻结）**：仅本地保存 **30 天或 50MB（先到为准）**；超限滚动删除；设置页提供「导出诊断日志」入口（用户手动分享给客服/开发）。

---

## 1. 目标与成功指标（Why）

### 1.1 核心痛点
旅游/日常社交拍照中，被拍者常因紧张而出现：表情僵硬、动作尴尬、不愿多拍、出片率低；拍摄者也挫败。现有相机/修图 App 多强调参数/滤镜/后期，忽视“拍摄当下的情绪状态”。

### 1.2 核心价值
让“拿手机的人”像导演一样给出**可执行的一句话指令**，让被拍者放松、愿意多拍，提升出片率。

### 1.3 北极星指标（本地统计）
- Session 内：拍了 X / 标记 ✅ 喜欢 Y / 收工导出 Z（仅本地存储）
- 引导有效性（本地）：达标次数、达标后 5s 内按快门的比例

---

## 2. 产品边界（定位与人群）

- 目标用户：海外旅行/出游/情侣/朋友聚会；“帮她拍（Shooter）”为主
- 核心场景（仅 2 个）：
  - 咖啡厅（cafe）
  - 户外地标（outdoor）

---

## 3. 信息架构（IA）与页面清单

> 本版本以「相机页为唯一核心页」为中心。其他均为 sheet / overlay / modal。

1. **Camera（主页面）**
2. **Album-like Viewer（相册级预览）**：从胶卷条进入（swipe/pinch/pan/doubleTap）
3. **Settings Sheet（设置）**：含 Pro 卡片入口、构图线开关、权限范围、导入照片、管理 Limited
4. **Pro Paywall Sheet（订阅）**：月付/年付（含 7 天试用）
5. **Inspiration Sheet（没灵感？）**：ODR 参考图挑选 + 关键词（离线可看词）
6. **Wrap / Collage Page（拼图/收工页）**：布局、选片、预览、保存/分享、继续拍
7. **Reset Confirm Modal（重置会话确认）**
8. **Down Reasons Sheet（不好看原因）**
9. **Center Modal（权限/告警/通用确认）**：权限引导、低空间预警、写入失败等

---

## 4. 核心功能（What）

### 4.1 拍摄心流（Camera Flow）
- 进入拍摄页 → 快门拍照 → **filmstrip 立刻出现缩略图（Optimistic UI：预览帧先飞入，后续替换为真实缩略图）** → 继续拍
- filmstrip：仅展示本次 Session 拍摄结果；**上限 20 张**；达到 **15 张强提醒**“请挑选/清空”
- **15 张强提醒触发规则（冻结）**：每个 Session 只触发一次；仅当 photo_count 从 14 → 15 跨越时触发。
- Session 达到 20 张：弹强提醒 + 行动按钮：
  - **清理未喜欢**：从“本次 Session 列表”移除所有未 ✅ 的照片（不删除系统相册里的原片，仅清理 session 工作集，减少卡顿）
  - 取消：关闭提醒（快门仍保持 disabled，直到用户清理未喜欢/去拼图/重置会话使 session 计数 < 20）

> 说明：此策略的目标是“filmstrip 不爆炸”，不是删除用户照片。

#### 4.1.3 Session 上限 20：快门/保存/可见性（冻结）

> 目标：杜绝“用户拍到了但在 App 里找不到”的数据安全灾难。

**计数口径（workset_count）**

* workset_count 统计 **当前 session 工作集内的条目数**，包含：`captured_preview/writing/thumb_ready/thumb_failed/write_failed`。
* `capture_failed` **不计入** workset_count。

**达到上限（workset_count == 20）**

* 立刻触发 L3 Modal：`已拍满 20 张，请先挑选或清理`
* 快门 **disabled**（直到 workset_count < 20）
* Modal 按钮（必须提供）：

  * `清理未喜欢`
  * `去拼图`
  * `重置会话`
  * `取消`（关闭 Modal；但快门仍保持 disabled，直至 workset_count < 20）

**上限期间的 filmstrip 行为**

* filmstrip 仍可浏览/点赞/进入 Viewer/清理未喜欢/重置
* 不允许任何方式新增 session 条目（拍摄新增条目不允许）

**验收口径**

* 20 张时快门不可点；取消后仍不可点；清理/重置后快门恢复
* 上限期间不会出现“写入系统相册成功但未进入 session 工作集”的照片

#### 4.1.1 可验收性能口径（冻结）

> **基准机型**：iPhone 11（A13）
> **统计口径**：以 p95 为主（除非另有说明）；若未标注，默认 p95。

**名词定义**
- **冷启动（Cold Start）**：App 不在内存中，从桌面首次打开。
- **热启动（Warm Start）**：App 从后台回到前台（切到微信/来电后返回）。
- **进入相机页到快门可点**：以 Camera 页面 `viewDidAppear` 为起点，到快门按钮 `enabled=true` 为终点。
- **Warmup overlay**：相机预览尚未可用/未稳定时覆盖在预览层的“准备中”遮罩；期间快门不可点。
- **Filmstrip hitch（卡顿）**：滑动/动画过程出现明显停顿；工程验收以“单次停顿时长”判定。
- **缩略图替换耗时**：按下快门到 filmstrip 中该项显示“真实缩略图（thumb_ready）”的时间。
- **Viewer 首帧显示耗时**：点 filmstrip 到 Viewer 出现图像内容（低清预览也算）的时间。

**SLO（验收阈值）**
- **启动到可拍（Camera Ready）**
  - 冷启动：p95 ≤ **3.0s**
  - 热启动：p95 ≤ **1.5s**
  - Warmup overlay：进入相机页立即显示；ready 后消失
  - 超时升级：> **3.0s** 文案升级为“相机准备中…（可能需要几秒）”
  - 失败判定：> **8.0s** 进入 L3 Modal：`相机初始化失败`（按钮：`重试` / `去设置`）
- **交互流畅**
  - Filmstrip：单次 hitch ≤ **100ms**；持续滑动 5 秒内 hitch ≤ 1 次
  - 缩略替换：p95 ≤ **1.5s**；> **5.0s** 记为 `thumb_failed`
  - Viewer 首帧：p95 ≤ **300ms**；p99 ≤ **800ms**；>800ms 显示加载占位；>3s 进入“加载失败可重试”

#### 4.1.2 相机权限与初始化失败分因（冻结）

> 目标：任何“相机不可用/初始化失败”必须可解释、可恢复、可验收。

**权限状态枚举（CameraAuth）**

* `not_determined`：未请求过相机权限
* `authorized`：已授权
* `denied`：用户拒绝
* `restricted`：系统限制（家长控制/企业配置等）

**首次进入相机页（not_determined）**

* 进入相机页展示 L3 Modal（预提示）：`Just Photo 需要相机权限才能拍照`

  * 按钮：`继续`（触发系统权限弹窗） / `取消`（退出到上一级页面；相机不可用）
* 若用户同意 → 进入 `authorized` 流程（warmup → ready）
* 若用户拒绝 → 进入 `denied` 流程（见下）

**denied / restricted**

* 相机预览区域展示占位（无实时预览），快门 **disabled**
* 顶部展示 L2 Banner：

  * denied：`未获得相机权限，无法拍照`（按钮：`去设置`）
  * restricted：`相机受系统限制，无法使用`（按钮：`了解`）
* 允许用户浏览 filmstrip/Viewer/设置页（若存在已拍内容）；但任何“拍摄相关入口”均不可用

**初始化失败分因（CameraInitFailureReason）**

* `permission_denied`（相机权限 denied/restricted）
* `camera_in_use`（被其他 App 占用/系统冲突）
* `hardware_unavailable`（设备不可用/异常）
* `unknown`

**Warmup > 8s 的失败态（L3 Modal）**

* 标题：`相机初始化失败`
* 主文案：必须包含 reason 对应解释（例如 camera_in_use：`相机可能被其他应用占用`）
* 按钮：

  * `重试`（重新初始化相机管线）
  * `去设置`（仅当 reason=permission_denied 时显示）
  * `取消`（返回相机页，但快门保持 disabled，直到用户重试成功或权限恢复）

**验收口径**

* denied/restricted 下：快门不可点；去设置跳转正确；返回后能正确刷新状态
* warmup 超时：>8s 必出失败 Modal；Modal 文案必须包含 reason；“重试”可重复触发

### 4.2 台词卡指导（Director Script Card）
- 拍摄页显示**单条台词卡**：拍摄者照读给模特
- **不提供 App 内置播报（冻结）**：MVP 不接入 TTS（不使用 AVSpeechSynthesizer）。若系统 VoiceOver 开启，则由 iOS 无障碍朗读 UI 文案，且展示/节流时长使用 Appendix A 的 `VOICEOVER_*` 常量。
- 台词卡要求：一次只说一件事、3 秒内能理解并执行
- 更新节奏：同一条台词卡至少展示 ≥ 3s
- 插队规则：通常遵循 *光线 → 构图 → 姿态 → 表情*；但当问题严重可插队（例如光线极端导致无法识别表情）

### 4.3 夸夸（Praise）
- 夸夸触发：跨过 exit 阈值（达标）时触发；同一维度 10 秒内最多夸一次（冷却）
- 达标后冻结：达标即夸 → 台词卡锁定「就现在！按快门」直到用户拍照或 5s 超时
- 不稳定策略：收回夸夸，台词卡明确提示“不稳定原因 + 对应指令”

### 4.4 端上检测与规则引擎（PoseSpec Engine）
- iOS 16+；Vision 端上推理；不调用外部推理 API
- PoseSpec（JSON）为单一事实源，随 App 版本发布；schemaVersion 版本化；QA before/after 资产用于回归验收

#### 4.4.1 PoseSpec 合约与版本一致性（冻结）
- **唯一输入**：App Bundle 内置的 `PoseSpec.json`（不得远端拉取/热更新）；加载失败视为 **L3 致命**（见 4.2 提示等级表）。
- **版本一致性**：
  - PoseSpec 内必须包含 `schemaVersion`、`prdVersion`、`generatedAt`、`changeLog`。
  - `prdVersion` 必须与本 PRD 的“当前版本”一致；不一致视为 **构建错误**（禁止提测/上架）。
  - 任一行为/阈值/文案若与 PoseSpec 冲突，以 **PoseSpec 为准**（但 PRD 的冻结条款约束 PoseSpec 的最小内容，见 4.4.2～4.4.7）。
- **场景一致性**（与 PoseSpec.sceneCatalog 对齐）：
  - UI/Analytics 仅允许 `cafe | outdoor`。
  - 允许存在内部共享场景 `base`（**仅引擎内部**；不得出现在 UI、埋点 `analytics.scene`、或导出日志的“用户可见字段”里）。
  - 评估规则：永远同时评估 `base + 当前 uiScene`。

**验收口径**
- 给定：改动 PRD 版本号但未同步 PoseSpec.prdVersion → Then：构建/CI 必失败（或 App 启动 L3 阻断并明确提示“版本不一致”）。
- 给定：UI 选择 cafe/outdoor → Then：引擎实际评估必须包含 base 场景 cues（可通过本地诊断日志验证）。

#### 4.4.2 Landmark 变量绑定规则（冻结）
> 目标：PoseSpec 里 `metric.landmarks` 与 `metric.formula` 的变量名必须有**唯一且可复现**的解析规则，杜绝实现方各写各的。

- PoseSpec 顶层必须提供 `binding` 字段，至少包含：
  - `aliases`：公式变量名 → `metric.landmarks` 的 canonical 路径（示例：`lShoulder → body.leftShoulder`）。
  - `sets`：集合变量的定义（示例：`bodyPoints`）。
- **最小 alias 集合（必须提供）**：
  - `lShoulder, rShoulder, lHip, rHip, lAnkle, rAnkle`
  - `faceBBox, noseTip, chinCenter`
  - `lEye, rEye, eyeMid, hipMid, ankleMid`
  - `bodyPoints`（集合）
- **集合变量定义（必须写死）**：
  - `bodyPoints`：`metric.landmarks` 中所有 `body.*` 点里 **confidence ≥ defaults.confidence.minLandmarkConfidence** 的可见点集合（缺失点忽略）。

**验收口径**
- 给定：同一条 cue 在两套实现（iOS/QA 脚本）计算 → Then：输出的 `metric.outputs` 数值误差 ≤ 1e-3（normalized space）。
- 给定：PoseSpec 中引用了别名变量但 `binding.aliases` 缺失该映射 → Then：该版本 PoseSpec 判定为 **无效**（启动 L3 阻断并提示“PoseSpec 不完整：binding 缺失”）。

#### 4.4.3 ROI 词典与帧级指标口径（冻结）
> 目标：所有 `meanLuma(*) / highlightClipPct(*) / edgeDensityBG(*) / registration(*)` 必须在**同一 ROI 定义**下可复现。

- PoseSpec 顶层必须提供 `rois` 字段（ROI 字典），至少包含：`faceROI`、`eyeROI`、`bgROI`。
- ROI 坐标系：与 PoseSpec.coordinateSystem 保持一致（normalized image space，x/y ∈ [0,1]）。
- **faceROI（冻结）**
  - 来源：`face.faceBBox`
  - padding：x/y 方向各 **+15% bbox 尺寸**
  - clamp：超出画面边界部分裁剪到 [0,1]
- **eyeROI（冻结）**
  - 来源：`face.leftEyeCenter` 与 `face.rightEyeCenter`
  - 规则：以两眼中点 `eyeMid` 为中心，宽 = **2.2×眼距**，高 = **1.2×眼距**；clamp 到 [0,1]
  - 若任一眼 confidence < defaults.confidence.minLandmarkConfidence：eyeROI 不可用（该依赖 eyeROI 的 cue 必走 fallbackCueId）
- **bgROI（冻结）**
  - 语义：`fullFrame - faceROI` 的“环形背景”
  - 实现口径：以 4 个矩形拼接近似（top/bottom/left/right 四块，按面积加权求均值）；不得将 faceROI 内容计入 bgROI
- 帧级指标采样口径（冻结）：
  - 仅使用相机预览帧（不得阻塞拍照/保存管线）。
  - `updateHz` ≤ 2 的 T1 cue：允许按最新可用帧采样（丢帧不补算）。

**验收口径**
- 给定：同一张静态截图作为 frame 输入 → Then：不同实现计算的 meanLuma/edgeDensity/highlightClipPct 误差 ≤ 2%（相对误差）。
- 给定：eyeROI 不可用 → Then：依赖 eyeROI 的 cue 不得触发；必须 fallback 到其 `fallbackCueId`。

#### 4.4.4 withRef 目标值（target.*）提取口径（冻结）
- 当用户选中参考图时，引擎必须对参考图运行与实时相同的 **PoseSpec metric 计算链**，得到 `target`（只保存必要输出，不保存原图像素）。
- `target` 的存储：仅本地、仅当前 Session；重置会话即清空。
- 若参考图无法通过 5.2 的强门槛 → withRef 必须不可用（只允许 noRef）。

**验收口径**
- 给定：同一张参考图重复选择 → Then：target 输出稳定（同一设备上前后两次误差 ≤ 1e-3）。
- 给定：重置会话 → Then：target 被清空；提示逻辑回到 noRef。

#### 4.4.5 镜像评估策略（冻结）
> 目标：实现“允许左右镜像”且可验收，不靠主观。

- 当 withRef 启用且 cue.trigger.withRef 存在时：
  - 必须同时计算 **非镜像误差** 与 **镜像误差**，取较小者作为最终误差。
  - 镜像定义：以画面竖直中线 x=0.5 做左右翻转；所有参与该 metric 的点位 x 坐标按 `x' = 1 - x` 变换（y 不变）。
  - 若最终选择了镜像误差：`mirrorApplied=true`（仅内部/本地日志可见；UI 不必显式提示）。
- 若 cue 的 metric 仅包含与 x 无关的量（例如亮度/roll/pitch proxy）：允许将镜像评估视为等价并省略。

**验收口径**
- 给定：参考图为左构图，实时画面为其左右镜像 → Then：在镜像策略开启时应触发“达标/接近达标”；关闭镜像策略时应明显偏离（可用 QA 资产对照）。

#### 4.4.6 性能预算与降级口径（冻结）
- **绝对原则**：PoseSpec 引擎不得阻塞相机预览、快门响应、写入相册队列（Data Safety 优先于提示）。
- **分层计算（冻结）**：
  - `computeTier=T0`：轻量几何（pose/face landmarks）允许最高 15Hz。
  - `computeTier=T1`：帧级/ROI 指标（luma/edgeDensity/highlight/registration）最高 2Hz。
- **降级触发（冻结）**：任一条件成立即降级，恢复条件满足后再逐步恢复：
  1) `ProcessInfo.thermalState >= serious`  
  2) 预览渲染持续掉帧（连续 1s 内 droppedFrames ≥ 5 或平均 FPS < 24）
- **降级动作（冻结）**：
  - 先停用所有 T1 cue（只保留 pose/compose 类 T0）
  - 再将 T0 updateHz 降至 8Hz
  - 降级期间：不得弹“引擎出错”类提示；仅允许提示 `FRAME_GENERAL`（温和兜底）。

**验收口径**
- 基准机型 iPhone 11：开启 PoseSpec 后，4.1.1 的 Camera Ready/Filmstrip/View SLO 不得退化超过 10%（p95）。
- 触发热/掉帧降级时：提示仍可用但降频；快门与保存流程不受影响。

#### 4.4.7 头部姿态/视线（V1 代理定义，冻结）
> 说明：V1 不要求“真实眼球注视方向”建模；采用可计算的代理指标以满足“必须参与”的产品口径，并可回归。

- **头部姿态（V1 代理）**至少包含：
  - `eyeLineAngleDeg`：作为 headRoll 代理（眼线倾斜）
  - `noseToChinRatio`：作为 headPitch 代理（脸朝上/朝下的近似）
- **视线（V1 代理）**至少包含：
  - `EyesVisible`：左右眼 confidence 均 ≥ minLandmarkConfidence
  - `EyeCatchlightProxy`：`meanLuma(eyeROI) - meanLuma(faceROI)`（眼睛相对脸更暗则提示“看向光/抬眼找光”）
- 若 V1 代理不可计算（缺 eyeROI/faceROI）：该维度不触发“强匹配达标”，并必须 fallback 到 `FRAME_GENERAL`（或对应 fallbackCueId）。

**验收口径**
- 给定：眼线明显倾斜（roll） → Then：应触发相关矫正 cue；矫正后退出阈值明确。
- 给定：眼部明显过暗 → Then：应触发“眼睛看向光”类 cue；满足 diff≥阈值后退出。


### 4.5 单人主角锁定（Single-Subject Lock）
- **暂停/继续（冻结）**
  - `暂停`：展示 L2 Banner「主角消失：请把她拉回画面」；暂停期间引擎不更新主角/不更新相关口令，但相机预览与快门仍可用
  - `继续`：恢复引擎更新；优先使用用户最近一次手动选中的主角；若无则自动选择“中心/最大脸”
  - 用户可在暂停期间点按重新选主角；一旦选中即自动退出暂停
- 多人/路人出现时：默认中心/最大脸锁主角；支持点按锁定（锁定框 UI；纠错一次点按）
- 主角丢失：提示“主角消失”，用户可选暂停或继续；继续时优先手动选，否则自动选新主角

---

### 4.6 Wrap（拼图/导出）

#### 4.6.1 Wrap/拼图页面级冻结规格（冻结）

**入口**

* workset_count ≥ 3 显示「拼图」；<3 不显示；异常进入则 L3：`照片不足，无法拼图`

**默认选片**

* 默认选本 session 最近 N 张（模板决定 N=3 或 4），不要求 liked
* 若存在 `write_failed`：禁止进入 Wrap（先处理保存失败）

**交互（最小集合）**

* 模板：仅 `1×3` 与 `2×2`
* 支持替换：点格子→底部选择条（来自本 session）→选择替换
* 不支持：自由裁切拖动/滤镜/贴纸/文字/边框（写入 Non-Goals）

**导出**

* 1080×1920，center-crop；保存到系统相册并尽力归档到 Just Photo 相册
* 分享使用系统分享面板；用户取消分享不提示错误

**失败态**

* 无权限/相册不可用：L3：`无法保存拼图`（去设置/取消）
* 空间不足：L3：`存储空间不足`（去清理/取消）
* 生成失败：L3：`生成失败，请重试`（重试/取消）

**验收口径**

* 默认选片正确；可替换；导出成功可在系统相册找到；失败态弹窗正确

## 5. 参考图（withRef）与 ODR（核心闭环）

### 5.1 参考图强匹配（withRef）
- 用户可添加多张参考图；**以当前选中的参考图为准（仅显示当前一张叠加）**
- 匹配维度（冻结）：
  - 姿态：相对位置为主（躯干/骨架坐标系相对坐标）
  - 头部姿态/视线：必须参与
  - 构图：相对裁切坐标，安全构图区间允许 ±10% 偏差
  - 镜像：允许左右镜像
- withRef/noRef：withRef 优先；缺指标或检测不足可回退 noRef


#### 5.1.1 withRef V1 最小可实现口径（冻结）
> 目标：把“强匹配”落到 **PoseSpec 可度量输出** 上；所有维度必须可计算、可回归。

- V1 的强匹配由以下 **可计算维度** 组成（均来自 PoseSpec `metric.outputs` 或其冻结代理，见 4.4.7）：
  1) **构图 / 裁切**：`centerXOffset`、`centerYOffset`、`headroom`、`bottomMargin`、`bboxHeight`  
  2) **躯干/骨架相对姿态**：`shoulderAngleDeg`、`hipAngleDeg`、`torsoLeanAngleDeg`
  3) **头部姿态（V1 代理）**：`eyeLineAngleDeg`（roll proxy）、`noseToChinRatio`（pitch proxy）
  4) **视线（V1 代理）**：`EyesVisible` + `EyeCatchlightProxy`（`meanLuma(eyeROI)-meanLuma(faceROI)`）
- **强匹配（Match）口径冻结：一律以 PoseSpec 的 `withRef.exit` 为准**（详见 5.1.1.a）。
- **当前 PoseSpec（v1.1.4）下的裁切/构图类维度 Match 区间（用于 QA/实现对照；数字来源=对应 cue 的 withRef.exit）**：
  - `centerXOffset`：`-0.04 ≤ (centerXOffset-target.centerXOffset) ≤ +0.04`（由 `FRAME_MOVE_LEFT/RIGHT` exit 推导）
  - `centerYOffset`：`-0.06 ≤ (centerYOffset-target.centerYOffset) ≤ +0.06`（由 `FRAME_MOVE_UP/DOWN` exit 推导）
  - `headroom`：`(headroom-target.headroom) ≥ +0.09`（由 `FRAME_ADD_HEADROOM` exit 推导；只做“加头顶空间”单向约束）
  - `bottomMargin`：`(bottomMargin-target.bottomMargin) ≥ +0.05`（由 `FRAME_DONT_CROP_FEET` exit 推导；只做“别裁脚”单向约束）
  - `bboxHeight`：`-0.06 ≤ (bboxHeight-target.bboxHeight) ≤ +0.05`（由 `DIST_STEP_CLOSER/BACK` exit 推导；消除“无提示但不达标”缝隙）
- “骨架坐标系相对坐标”的冻结定义（用于姿态/构图统一坐标系）：
  - 坐标系以 `bbox(bodyPoints)` 为主：中心为 personBBox center；尺度以 personBBox 的 height 为归一化基准。
  - 所有相对量必须在该坐标系中计算（从而保证不同分辨率/机型一致）。

**验收口径**
- 给定：同一张参考图 + 静态实时画面完全一致 → Then：强匹配维度误差应全部进入 exit 区间；并触发“就现在！按快门”（夸夸冻结策略见 4.3）。
- 给定：仅构图左右镜像一致（姿态/光线一致） → Then：镜像策略开启时应判定可达标（或明显接近达标）。
- 给定：参考图不满足 5.2 强门槛（多人/眼不可见/肩不可见） → Then：withRef 不得启用；必须退回 noRef，并给出可见原因。

#### 5.1.1.a Match（达标）判定口径冻结（Blocker）

> 目标：杜绝“UI 安静但不达标”的死锁；确保达标/夸夸/快门锁定与 PoseSpec 完全一致。

- **唯一规则**：withRef 的 `Match=true` **必须等价于**：本节 5.1.1 定义的所有强匹配维度，其对应的 PoseSpec cue（或维度判定器）均处于 **exit** 状态（连续满足 ≥ `persistFrames`）。
- **严禁** 在代码里另起一套硬编码阈值（例如 bboxHeight 误差 <2% 之类）。若阈值需要更严/更松，只能改 PoseSpec 的 `trigger.*.exit`。
- 若某维度因缺 landmarks/缺 ROI/低 confidence 而触发 withRef 回退（见 5.1.2），则该维度 **不得计入 Match**；`Match` 必须为 false（可继续给“接近达标/可拍建议”，但不得触发“就现在！按快门”）。
- **注意**：UI “无 cue 展示/安静”不是独立判定；达标必须以引擎的 `Match` 状态为准。

**验收口径**
- Given：withRef 启用，且引擎报告所有强匹配维度均满足 exit（连续 ≥ persistFrames）
  - Then：必须触发 4.3 的夸夸（“就现在！按快门”锁定，直到拍照或 5s 超时）
- Given：UI 处于安静（无 cue），但任一强匹配维度未满足 exit
  - Then：不得触发达标/夸夸/倒数；且必须在本地诊断日志记录 `match_blocked_by=[dimensionIds...]`

#### 5.1.2 withRef 回退与不可用原因（冻结）
- 当任一强匹配维度缺失（缺 landmarks / 缺 ROI / 低 confidence）时：
  - **不得沉默**：必须在本地诊断日志中记录 `withRefFallbackReason`（例如 `missing_eyeROI` / `low_confidence_shoulders`）。
  - UI 行为：不需要打扰用户（默认继续提示 noRef），但不得出现“明明选了参考图却一直不对齐”的无解释假象。
- 当仅部分维度缺失时：
  - 仍可用 withRef，但 **达标判定** 必须明确：缺失维度不得计入“已达标”；只能计入“接近达标/可拍建议”。

**验收口径**
- 给定：遮挡导致眼 ROI 不可用 → Then：不允许触发依赖眼 ROI 的 withRef 达标；必须按冻结策略回退并可追溯原因（本地日志）。


### 5.2 参考图导入与强门槛（冻结）
- 来源：用户相册选择（优先）或「没灵感？」选择 ODR 内置参考图
- **一律复制一份到系统相册的 Just Photo 相册**（保证可读/可离线匹配），并在 App 内标记“参考图”；UI 明示“仅用于参考”
- 首次保存系统参考图时弹一次告知：
  - “将把参考图保存到「Just Photo」相册，仅用于参考，可随时删除。”
- 强门槛：检测失败直接提示“这张不适合做参考图，请换一张”，并给原因：多人/脸太小/看不到眼睛/上半身不全等

#### 5.2.1 参考图强门槛：可计算规则（冻结）

> 目标：拒绝理由必须“可计算、可复现、可验收”。

- **多人（Multi-person）**：检测到 **≥2 张人脸**（faceConfidence ≥ 0.6）→ 拒绝
- **脸太小（Face too small）**：满足其一即拒绝
  - faceBBox 面积占画面比例 `< 2.0%`（areaRatio < 0.02）
  - 或 faceBBox 宽度 `< 12%` 画面宽（widthRatio < 0.12）
- **看不到眼睛（Eyes not visible）**：leftEyeCenter.conf < 0.5 **或** rightEyeCenter.conf < 0.5 → 拒绝
- **上半身不全（Upper body incomplete）**：leftShoulder.conf < 0.5 **或** rightShoulder.conf < 0.5 → 拒绝

提示文案要求：必须包含“拒绝原因 + 下一步建议”（例如“脸太小：请靠近一些/让脸占画面更大”）。
- **参考图副本上限（冻结）**：
  - **单次拍摄任务（一个 Session）最多保存 10 张参考图副本**到 Just Photo 相册
  - 用户可通过“重置会话”开始下一组任务（重置后重新累计 10 张）
- 参考图永远不计入 Session 统计

### 5.3 ODR 内置参考图库（500 张真实照片）
- 500 张真实参考图以 App Store ODR 托管；不自建后端；随发版更新
- 无网退化：没灵感页不可用 ODR 图，但仍可看“灵感搜索词”；用户自带参考图若已在 Just Photo 相册则可用
- ODR 下载策略：用户点选哪张就请求对应 tag（按小包切分），避免一次性下载大量资源

#### 5.3.1 Inspiration Sheet 状态（冻结：必须可验收）

定义 4 个状态（页面级）：
- `ready`：可用（有网且 ODR 可请求）
- `downloading`：正在下载（展示进度/骨架；允许取消）
- `failed_retry`：下载失败（展示失败原因；按钮：重试）
- `offline_keywords_only`：离线退化（仅显示关键词；ODR 图区域隐藏或置灰并提示“需要网络”）

触发规则（最小口径）：
- 无网络 → `offline_keywords_only`
- 有网络且首次进入/用户点选 ODR 图 → `downloading` → 成功进入 `ready`（并允许选择）
- 下载中断/失败（含蜂窝限制/磁盘不足）→ `failed_retry`

**网络恢复自动重试（冻结，提升可用性）**
- 当页面处于 `failed_retry` 时：必须启动网络恢复监听（`NWPathMonitor` 或等价机制）。
- 当网络从 `unsatisfied` → `satisfied`：
  - 若用户仍停留在 Inspiration Sheet 且状态仍为 `failed_retry`，则在 **debounce 500ms** 后自动触发 **一次** `重试`（每次网络恢复最多 1 次）。
  - 自动重试成功 → 转 `ready`；自动重试失败 → 仍保持 `failed_retry`，并保留手动 `重试` 按钮（不得进入“半死”状态）。
- 用户离开该页面：必须停止监听并取消待执行的自动重试。

**验收口径**
- Given：离线点击 ODR 触发失败进入 `failed_retry`
- When：网络恢复
- Then：无需用户额外操作，状态应自动从 `failed_retry` 触发一次重试并进入 `ready`（或可解释地仍为 `failed_retry` 且按钮可用）


### 5.4 达标后“下一张参考图”轻提示
- 达标后锁定“按快门”5s
- 用户拍下达标照后：弹轻提示“要不要拍下一张参考图？”
  - 不操作：保持当前参考图
  - 用户通过“上一张/下一张”切换继续拍

---

## 6. 相册/权限与数据（Data Safety & Photos）

### 6.1 写入策略（即拍即存）
- 永远即拍即存：试用/到期都照样写入系统相册
- 尽力归档到 `Just Photo` 专属相册
- 失败兜底（必须）：写入失败必须提示并给行动入口（去设置/清理空间）；不允许 silent failure；**写入失败必须阻断快门直至用户处理（重试成功或放弃该张）**。

#### 6.1.1 保存管线状态机（冻结：Optimistic UI + 可验收）

> 目标：用户按下快门后，“我拍到没/我保存没/我还能不能找回”必须可解释、可验收。

**核心口径**
- **拍摄失败（capture_failed）**：未获得图像数据（真正意义“没拍到”）。
- **保存失败（write_failed）**：已获得图像数据，但未能写入系统相册（“拍到了但没保存成功”）→ **必须阻断快门**。
- **归档失败（album_add_failed）**：已写入系统相册，但未能归档到 `Just Photo` 专属相册（“保存成功但归档失败”）→ 不阻断，但提示修复。

**SessionItem 状态**
- `captured_preview`：按快门后立刻插入 filmstrip 项，显示预览帧/占位图（optimistic）
- `writing`：写入系统相册中
- `write_success(assetId)`：写入系统相册成功（拿到 assetId）
- `write_failed(reason)`：写入系统相册失败
- `album_add_success` / `album_add_failed`：归档到 Just Photo 相册成功/失败（不影响 write_success）
- `thumb_ready`：真实缩略图可用，替换预览帧
- `thumb_failed`：超过 **5.0s** 未替换为真实缩略图（仍可查看原图）

**thumb_failed 的自愈与永久失败（冻结）**

* 触发：从 `captured_preview` 开始计时，> **5.0s** 未获得真实缩略图 → 标记为 `thumb_failed`（显示 `!`）
* **迟到自愈**：若后续任何时刻生成真实缩略图成功，必须自动切换为 `thumb_ready` 并清除 `!`
* **永久失败**：> **30s** 仍无真实缩略图 → 视为永久失败；Viewer 顶部提示提供按钮：`重建缩略`

**filmstrip UI 显示规则**
- `captured_preview` / `writing`：显示预览帧 + 右上角“保存中”指示（不遮挡主体）
- `thumb_ready`：显示真实缩略图
- `thumb_failed`：保留预览帧（若有）+ 右上角 `!`；点按可进 Viewer（顶部提示“缩略生成失败，不影响原图”）
- `write_failed`：灰底 + 右上角 `!`；点按进入 Viewer（方案 A：可查看未保存预览 + 支持重试/放弃）

**Viewer 行为（方案 A：已确认）**
- `write_failed` 进入 Viewer：顶部红条 `未保存到系统相册`；按钮：`重试保存` / `放弃此张`
- `重试保存`：
  - 成功：状态切换为 `write_success`（并继续尝试 `album_add_*`），filmstrip 恢复正常
  - 失败：保持 `write_failed`，展示失败原因（见提示等级表）
- `放弃此张`：从 session 工作集移除该项（不影响系统相册，因为本来未写入）

**写入失败的常见原因（用于 reason 枚举）**
- 权限不足（照片写入权限 denied/restricted）
- 存储空间不足
- 系统相册不可用/异常（受限/临时错误）
- 极端内存/系统压力导致写入失败

#### 6.1.2 capture_failed：拍摄失败（冻结）

**定义**

* `capture_failed`：未获得图像数据（真正意义“没拍到”）。

**UI 规则**

* 不插入 filmstrip 条目（避免“空卡片”污染工作集）
* 立即展示 L1 Toast：`拍摄失败，请重试`
* 若可判定原因（如相机被占用/权限问题/过热），Toast 文案追加原因短语（不超过 12 字）

**计数与上限**

* `capture_failed` **不计入** workset_count（不消耗 20 上限）
* 不触发 15 张强提醒逻辑

**升级规则（防刷屏）**

* 若 30 秒内连续发生 ≥3 次 `capture_failed`：升级为 L3 Modal：`相机异常`（按钮：`重试` / `去设置` / `取消`）

  * `去设置` 仅在可能为权限问题时显示

**验收口径**

* `capture_failed` 不产生 filmstrip 项；不增加计数；可重试；达到阈值后必升级 Modal

#### 6.1.3 并发拍摄与全局阻断策略（冻结）

> 目标：避免并发导致的“乱序/漏存/无法验收”。

**In-flight 队列上限**

* 允许同时存在最多 **2 个** in-flight 条目（状态为 `captured_preview/writing`）。
* 当 in_flight_count == 2 时：快门 **disabled**；展示 L2 Banner：`保存中…`（无按钮；in_flight_count < 2 后自动消失并恢复快门）

**write_failed 的全局阻断**

* 任意一张进入 `write_failed`：立即全局阻断快门（disabled），并弹出 L3 Modal：`有照片未保存，请先处理`

  * 按钮：`查看并处理`（跳转到该失败项 Viewer） / `取消`（关闭 Modal；但快门仍 disabled 直至失败项被处理）
* 其他 in-flight 项允许继续完成写入与缩略替换；filmstrip 正常更新

**验收口径**

* 并发最多 2；达到 2 快门必禁用且自动恢复
* write_failed 出现后：无论用户是否关闭 Modal，快门都不可用，直到失败项被处理

#### 6.1.4 album_add_failed：归档失败修复策略（冻结）

**触发**

* `write_success` 后尝试将照片加入 `Just Photo` 专属相册失败 → `album_add_failed`

**用户可见提示**

* Session 内首次发生 `album_add_failed`：展示 L2 Banner：`部分照片未归档到 Just Photo 相册`（按钮：`重试归档` / `稍后`）
* `稍后`：Banner 关闭；同 session 不再自动弹出；设置页必须提供“重新归档”入口

**重试策略**

* 用户点 `重试归档`：对“本 session 中所有 album_add_failed 项”批量重试一次
* 自动重试：同一张最多自动重试 **3 次**（退避：1s/3s/10s）；超过后停止自动重试
* 下次启动：若存在未归档项，进入相机页后自动重试一次（不弹窗，仅在失败时再次显示 Banner）

**验收口径**

* 归档失败不阻断拍摄；Banner/设置入口可重试；成功后状态清除

### 6.2 权限策略（可实现口径冻结：iOS 16+）
- 接受 **Limited Access**：用户只授权部分照片
- 可读范围口径：**用户授权的那部分 + 我们新写入的 assets**
- App 内历史/浏览：以作品集 identifiers 为准（不保证“只读某个相册”，但保证“不读全库”）
- Favorite 同步：尽力同步系统 Favorite；失败时每个 Session 提醒一次；用户可选择仅 App 内 liked

### 6.3 设置页必须提供的权限管理入口（冻结）
- 「管理已选照片（Limited Picker）」：调系统 Limited Library Picker（让用户补选更多可读照片）
- 「去系统设置」：跳转系统设置页（用于彻底改为 Full 或排障）

### 6.4 导入照片（Import to Session）— MVP 保留
- 用户可从系统选择若干照片导入当前 session（用于拼图/挑选）
- 在 Limited 下：导入动作本身会通过系统 picker 扩展“已授权集合”（仍符合 Limited 口径）
- 导入后的照片进入“session 工作集”，遵守 session 上限与清理规则（不影响系统相册）

---

## 7. UI 规范（工程可落地）

### 7.1 Camera（主页面）布局模块
- **Top Bar**
  - 夸夸（按钮）
  - 场景切换（按钮）
  - 没灵感？（按钮）
  - 闪光（iOS 原生相机一致：Auto/On/Off 口径；实现按系统能力）
  - 重置会话（按钮）
  - 设置（按钮）
- **Camera Area**
  - Warmup overlay（相机准备中）
- **Warmup overlay 规则（冻结）**
  - 进入相机页立即显示；ready 后消失；warmup 时快门不可点
  - >3.0s：文案升级为“相机准备中…（可能需要几秒）”
  - >8.0s：L3 Modal：`相机初始化失败`（`重试` / `去设置`）
  - 构图线 overlay（可开关）
  - 台词卡（单条口令）
  - 夸夸 overlay（可展开/折叠；支持安静模式）
  - 参考图 overlay（仅当前一张）：60% 透明、两档大小（大/小）、可拖动、可隐藏、上一张/下一张切换
- **Bottom Bar**
  - 参考图（上传 / 从没灵感选）
  - 快门（始终可见；warmup 时不可点）
  - 胶卷条（仅拍过后出现；最新在前）
  - 拼图（>=3 张出现）
  - 不好看（>=10 张出现）

#### 7.1.1 参考图 overlay 硬规格（冻结）

- **尺寸**：两档大小
  - 小：overlay 宽度 = 取景区短边的 **20%**（等比缩放）
  - 大：overlay 宽度 = 取景区短边的 **30%**（等比缩放）
- **透明度**：60%（保持不变）
- **拖动边界**：允许在取景区内自由拖动；不自动吸附边缘；必须 clamp 在安全区内（不出屏）
- **遮挡规则**：不允许遮挡快门按钮（必须自动避让/限制拖动区域）；允许与台词卡重叠
- **层级**：参考图 overlay 与台词卡/夸夸可重叠，但不得盖住系统弹窗/Modal

#### 7.1.2 夸夸 overlay：控件语义（冻结）

**控件与行为**

* `👍`：本地反馈（不上传）；L1 Toast：`已记录`；相同文案 24 小时内不重复出现
* `👎`：本地反馈（不上传）；L1 Toast：`已记录`；立刻“换一句”；每 3 秒最多触发 1 次换句（防抖）
* `展开`：展开面板（当前建议 + 最近 2 条历史）；不得遮挡快门（遮挡则自动上移/缩小）
* `安静`：开启后不自动弹出夸夸 overlay（默认折叠）；用户仍可手动展开查看；Session 内有效

**验收口径**

* 👍/👎 均有 Toast；👎 必须立刻换句且节流生效；安静模式生效

#### 7.1.3 前后摄像头翻转（冻结）

* 默认后摄；翻转后显示 Warmup overlay，ready 后消失
* 翻转后退出单人主角锁定（回到自动选择）
* 参考图 overlay 状态/位置保持（在新预览坐标系内 clamp）
* session 工作集保持（不清空 filmstrip）
* 若翻转初始化失败：按 4.1.2 reason 弹 L3 Modal：重试/去设置（仅权限原因）

**验收口径**

* 翻转不丢 session；主角锁定重置；overlay 保持；失败按 reason

### 7.2 Album-like Viewer（相册级预览）
- 顶部：关闭 ×、预览计数 x/y、✅ 选中/取消
- 内容：单图显示 + 手势层（swipe/pinch/pan/doubleTap）
- 关键规则：
  - Viewer 顺序必须与胶卷条顺序一致（最新在前）
  - scale>1 时：禁止左右翻页（只允许拖动）；scale==1 时才允许 swipe 翻页
  - **边界（冻结）**：scale <= **1.01** 视为 1；超过 1.01 视为缩放态
  - **手势优先级（冻结）**：pinch 优先于 swipe；当 pinch 发生时，忽略同一手势序列中的翻页判定

### 7.3 Settings Sheet（设置）
- 顶部卡片：Just Photo Pro（显示订阅状态；点击进入订阅 sheet）
- 构图线开关
- 权限范围说明（Limited 口径 + 可读范围）
- 管理已选照片（Limited Picker）
- 去系统设置
- 导入照片（Import to Session）

### 7.4 Pro Paywall Sheet（订阅）
- 购买失败/无网：展示 L3 Modal：`无法完成购买`（按钮：`重试` / `稍后` / `检查网络`）
- 恢复购买失败/无网：展示 L3 Modal：`恢复失败`（按钮：`重试` / `稍后`）；并提供「管理订阅」跳转
- **7 天试用（StoreKit 口径）**：试用由 App Store 计时与结算；仅当用户完成订阅购买且产品配置包含试用时生效。UI 仅展示“试用中/到期日/权益”。
- 计划：月付 / 年付
- 主按钮：开通/确认
- 次按钮：取消
- 辅助：恢复购买 / 管理订阅（走 iOS 原生）

### 7.5 Inspiration Sheet（没灵感？）
- ODR 参考图挑选（有网可用）
- 关键词列表（随场景变；离线可看）
- 选中 ODR 图：会触发“复制到系统相册 Just Photo 相册”并设为当前参考图（遵守参考图上限）

### 7.6 Reset Confirm Modal（重置会话确认）— MVP 冻结
- 触发：点 Top Bar「重置会话」
- 二次确认文案必须“强提醒”：
  - 将清空：session photos、已用集合（used）、收工/拼图状态（wrap）、参考图列表（当前任务）
  - 不会删除：系统相册里的照片（仅清理 app 内 session 工作集）
- 确认后：回到 S0（首次拍照前）

### 7.7 Down Reasons Sheet（不好看原因）— MVP 最小版本（本地）
- 触发：>=10 张出现「不好看」入口
- 行为：打开原因列表（单选或多选皆可，但 MVP 建议单选）
- 结果：仅本地记录（不上传）；不影响台词卡/夸夸策略（V1 不闭环到引擎）

---

## 8. 功能拆解（Epic → Stories）

### Epic A：拍摄闭环（Camera → Filmstrip → Viewer → ✅ → Continue）
- A1 warmup + 快门可点性
- A2 Optimistic 缩略与保存状态
- A3 胶卷条出现规则（S0 无胶卷；S1 有胶卷）
- A4 Viewer 手势与一致性（顺序一致；scale>1 禁翻页）
- A5 ✅ liked + Full 权限下尝试同步系统 Favorite（失败不阻断）

### Epic B：灵感供给（台词卡/夸夸/没灵感）
- B1 场景切换（cafe ↔ outdoor）
- B2 夸夸 overlay（含安静模式）
- B3 没灵感（ODR 挑图 + 关键词复制 + 退化策略）

### Epic C：参考图（上传 + 叠加 + withRef）
- C1 参考图导入与强门槛
- C2 参考图 overlay（两档/拖动/隐藏/上一张下一张）
- C3 withRef 评估优先与 fallback noRef
- C4 参考图副本上限（10/Session）与重置后重新累计

### Epic D：拼图（Wrap / Collage）
- D1 入口（>=3 张出现）
- D2 布局：1×3 / 2×2
- D3 预览：1080×1920（9:16），每格 center-crop 填满
- D4 保存/分享（iOS 原生能力落地）

### Epic E：设置与订阅（Pro）
- E1 Pro 卡片与订阅状态展示
- E2 7 天试用
- E3 月/年订阅 + 恢复购买 + 管理订阅跳转
- E4 到期降级：关闭台词卡 + 关闭夸夸；拍照保存继续

### Epic F：会话管理与反馈
- F1 重置会话（二次确认 + 清空范围）
- F2 session 达到 20 的“清理未喜欢”机制
- F3 不好看原因 sheet（本地记录）

---

## 9. 埋点清单（最小｜仅本地）

> 仅写入本地日志/本地统计；不上传；不开任何远端 SDK。

### 9.1 事件（Event）
- camera_open
- shutter_tap
- photo_save_ok / photo_save_fail（含失败原因）
- filmstrip_open_viewer
- liked_toggle
- ref_add_user / ref_add_odr / ref_reject（门槛失败原因）
- ref_switch_next/prev
- inspiration_open / inspiration_select_odr / inspiration_copy_keyword
- wrap_open / wrap_export_ok / wrap_export_fail
- reset_open / reset_confirm
- down_reason_open / down_reason_select
- permission_status_change / open_limited_picker / open_settings

### 9.2 通用参数（params）
- scene（cafe/outdoor）
- session_id（本地随机）
- photo_index（0..）
- is_pro / trial_state
- auth_scope（limited/full）
- device（机型/系统版本，本地仅用于 debug）

---

## 10. QA 验收清单（关键路径）

1. 进入相机：warmup 立即出现；ready 后快门可点；冷启动 p95≤3.0s / 热启动 p95≤1.5s；>8.0s 进入“相机初始化失败（重试/去设置）”
1.1 保存状态机：按快门立刻出现 optimistic 预览；thumb p95≤1.5s；>5s 标记 thumb_failed 但可查看；write_failed 必须阻断快门并可在 Viewer 重试保存/放弃
1.2 相机权限：首次进入需预提示；denied/restricted 下快门 disabled 且提示去设置；warmup>8s 必弹含 reason 的失败 Modal
1.3 并发：in-flight≤2；达到2快门自动禁用并恢复；任一 write_failed 全局阻断直至处理
1.4 Session 上限：workset_count==20 快门 disabled；取消后仍 disabled；清理/重置后恢复
2. 首次拍照前：无胶卷条；拍完后：胶卷条出现且最新在前
3. 点胶卷缩略图打开 Viewer：计数正确；关闭可回相机
4. Viewer：scale<=1.01 视为 1 可左右翻页；scale>1.01 只能拖动不能翻页；双击缩放可回 1
5. ✅：切换 liked 状态，胶卷条与 Viewer 一致；Full 权限下同步 Favorite 失败不阻断但强提醒
6. 场景切换：口令/夸夸/没灵感随之更新
7. 没灵感：有网可选 ODR；无网退化为关键词；选 ODR 会复制到系统相册 Just Photo 相册并设为当前参考图
8. 参考图：上传后显示；两档大小/拖动/隐藏/上一张下一张可用；门槛失败提示原因
9. 参考图副本上限：同一 session 最多 10 张；超过必须强提示；重置后重新累计
10. filmstrip 上限：最多 20 张；15 张强提醒（每 session 仅触发一次：14→15）；workset_count==20 时快门 disabled；取消后仍 disabled；清理/重置后恢复（不删除系统相册照片）
10.1 thumb_failed 自愈：>5s 显示 `!`；后续缩略生成成功必须自动清除 `!`
10.2 归档失败：album_add_failed 不阻断；Banner/设置入口可重试；成功后状态清除
10.3 翻转相机：翻转不清空 session；主角锁定重置；参考图 overlay 状态保持；失败按 reason 弹窗
10.4 Wrap：>=3 可进；默认选片正确；可替换；导出成功/失败态弹窗正确
11. 拼图：>=3 张入口出现；1×3/2×2 切换预览更新；导出成功/失败提示正确
12. 设置：Pro 卡片存在；订阅状态正确；导入照片在 Limited 下可用且符合“已授权集合”口径
13. 设置：存在「管理已选照片（Limited Picker）」与「去系统设置」
14. 重置会话：二次确认；确认后清空 session photos/used/wrap/ref list 并回到 S0；不删除系统相册照片
15. >=10 张出现「不好看」入口，列表展示正确；选择后本地记录且不影响拍摄流程

---

## 11. 非目标（Non-Goals）

- 登录/账号体系、跨设备同步
- AI 修图、风格化滤镜、复杂手动参数
- 云端/账号、任何用户数据上报
- 多场景扩展（仅 2 场景）
- V1 不做“原因 → 引擎策略”的闭环（不好看原因仅本地记录）

- 视频 / Live Photo / 连拍（Burst）（性能/存储/权限复杂度显著上升，V1 明确不做）
- 复杂拼图模板、文字贴纸、边框（V1 仅 1×3 / 2×2）
- 自由裁切拖动（Wrap/拼图不提供手动调整裁切）
- 相册全库管理（仅按 Limited 口径读取；不做“全库浏览/清理/整理”）

---

## 12. 附录（冻结）

### 附录 A｜提示等级规范（Toast / Banner / Modal）（冻结）

| 等级 | 名称     | 是否阻断拍摄 |            默认时长 |             是否可堆叠 | 典型用途     | 必须包含                   |
| -- | ------ | -----: | --------------: | ----------------: | -------- | ---------------------- |
| L1 | Toast  |      否 |         2s 自动消失 | 否（同类 10s 内最多 1 次） | 轻提示/确认   | 简短文案（≤18字）             |
| L2 | Banner |      否 | 常驻直到用户关闭/自动条件消失 |       否（优先级低于 L3） | 可恢复问题提示  | 文案 + 0~1 个按钮           |
| L3 | Modal  |      是 |          必须用户决策 |           否（全局互斥） | 权限/失败/阻断 | 标题 + 原因 + 明确按钮（默认按钮写死） |

**全局调度规则（冻结）**

* L3 互斥：同时只允许一个 L3；新的 L3 到来时替换旧 L3（旧的记入日志）
* 系统权限弹窗优先级最高：出现系统弹窗时，App 内 L3 必须延后或在系统弹窗结束后再显示
* L2 与 L1：L2 可覆盖 L1；同类 L1 节流（10s 内最多 1 次）

---

#### A.0 目标与边界（冻结）
**目标**
1) **不打断拍摄心流**：除非“数据安全/无法继续”，否则不弹 L3。
2) **不允许 silent failure**：任何“未写入系统相册”必须可见且可行动；`write_failed` 必须阻断快门直到处理完成（重试成功或放弃该张）。
3) **同屏不刷屏**：同一时刻最多 1 条 Toast、1 条 Banner、1 个 Modal（或 1 条 Viewer 阻断条）。
4) **工程可落地**：所有提示必须来自 Prompt Catalog（A.7）；UI 仅渲染，不允许在 UI 层散落文案/节流/优先级判断。

**边界**
- 本附录只定义“提示系统”，不定义业务流程（业务流程以 PRD 主文为准）。
- 本附录允许补齐 PRD 未量化的边缘情况，但不得改变主文已冻结的口径（例如 `write_failed` 必须阻断快门）。

---

#### A.1 等级（Level）与 UI 落点（Surface）（冻结）
**Prompt Level**
- **L1 Toast**：轻提示；不阻断；自动消失；默认无按钮（最多 1 个可逆操作）。
- **L2 Banner**：状态/告警/可行动提示；不阻断主流程；可关闭；可带 1 个主按钮。
- **L3 Modal**：阻断/必须决策；不自动消失；必须按钮关闭。
- **Viewer 阻断条**：仅用于 `write_failed`，UI 形态为 Viewer 顶部红条；逻辑上等价 **L3**（阻断快门）。

**Prompt Surface**
- `cameraToastBottom`：拍摄页底部 Toast
- `cameraBannerTop`：拍摄页顶部 Banner（不得遮挡快门）
- `cameraModalCenter`：拍摄页中心 Modal
- `viewerBannerTop`：Viewer 顶部 Banner（非阻断）
- `viewerBlockingBarTop`：Viewer 顶部阻断红条（仅 write_failed）
- `sheetBannerTop`：Sheet 顶部 Banner（Settings / Paywall / Inspiration / Wrap）
- `sheetModalCenter`：Sheet 中心 Modal

**同屏互斥（强制）**
- 同一时刻只能同时存在：`1 Toast + 1 Banner + 1 Modal`；viewerBlockingBarTop 视为独立槽位（见 A.4）。

---

#### A.2 统一数据模型（必须照抄，不允许删字段）
##### A.2.1 枚举（必须齐全）
- `PromptLevel = {L1, L2, L3}`
- `PromptSurface = {cameraToastBottom, cameraBannerTop, cameraModalCenter, viewerBannerTop, viewerBlockingBarTop, sheetBannerTop, sheetModalCenter}`
- `WriteFailReason = {no_permission, no_space, photo_lib_unavailable, system_pressure}`
- `RefRejectReason = {multi_person, face_too_small, eyes_not_visible, upper_body_incomplete}`
- `FrequencyGate = {none, sessionOnce, installOnce, stateOnly}`
- `DismissReason = {auto, close, action, preempt}`

##### A.2.2 Prompt 实体（渲染输入）
Prompt 必须包含以下字段（缺一不可）：

- `key: String`（唯一标识，必须匹配 A.7 Catalog 的 key）
- `level: PromptLevel`
- `surface: PromptSurface`
- `priority: Int`（数值越大优先级越高）
- `blocksShutter: Bool`（仅允许 `write_failed=true`，其它一律 false）
- `isClosable: Bool`（L1=false；L2=true；L3=false；viewerBlockingBarTop=false）
- `autoDismissSeconds: Double?`（L1/L2 可有；L3/阻断条必须为 null）
- `gate: FrequencyGate`（见 A.3.3）
- `title: String?`（L3 必填；其它可空）
- `message: String`（必填）
- `primaryActionId: String?`
- `primaryTitle: String?`
- `secondaryActionId: String?`（L3/阻断条可用）
- `secondaryTitle: String?`
- `tertiaryActionId: String?`（仅 L3 允许；用于“检查网络/管理订阅”等第三按钮）
- `tertiaryTitle: String?`
- `throttle: ThrottleRule`（见 A.3.2）
- `payload: Dictionary<String, Any>`（仅用于模板填充/埋点；禁止影响节流/优先级逻辑）
- `emittedAt: Date`（用于同优先级“最新覆盖”）

##### A.2.3 ThrottleRule（字段固定）
- `perKeyMinIntervalSec: Double`
- `globalWindowSec: Double`
- `globalMaxCountInWindow: Int`
- `suppressAfterDismissSec: Double`

##### A.2.4 文案模板占位符（严格定义）
Catalog 的 `titleTemplate` / `messageTemplate` 允许使用以下占位符（仅这些）：
- `{reason}`：String（如写入失败原因、参考图拒绝原因）
- `{count}`：Int（如 Session 计数、失败张数）
- `{scene}`：String（场景名）
- `{seconds}`：Double（超时数值）
- `{mb}`：Int（空间阈值）

**模板替换规则**
- 占位符缺失：替换为空字符串，并自动清理多余空格/括号（不得显示 `{xxx}` 原文）。
- 数值格式：`seconds` 保留 1 位小数；`mb/count` 不带小数。

---

#### A.3 常量（必须量化，冻结）
##### A.3.1 自动消失时长
- `L1_TOAST_SECONDS = 4.0`
- `L2_BANNER_SECONDS = 6.0`
- `VOICEOVER_L1_TOAST_SECONDS = 6.0`
- `VOICEOVER_L2_BANNER_SECONDS = 8.0`

> 说明：本文的 `VOICEOVER_*` 指 **iOS 辅助功能 VoiceOver 开启时**的展示/节流口径；不是 App 自己做文字转语音。MVP **不得** 引入 AVSpeechSynthesizer 等 TTS。VoiceOver 开启时，toast/banner 必须提供可被朗读的 accessibilityLabel/traits，并按 `VOICEOVER_*` 时长控制。

**自动消失规则（deterministic）**
1) L1：一律自动消失
2) L2：若无 primary 按钮 → 自动消失；若有 primary 按钮 → 不自动消失（必须点 × 或点按钮）
3) L3 / viewerBlockingBarTop：不自动消失

##### A.3.2 默认节流（除非 Catalog 覆盖）
- L1 默认 throttle：`2.0 / 10.0 / 3 / 0`
- L2 默认 throttle：`10.0 / 20.0 / 2 / 60.0`
- L3 默认 throttle：`10.0 / 60.0 / 1 / 30.0`

##### A.3.3 Gate（频次门控）
- `none`：仅受 throttle 控制
- `sessionOnce`：每个 Session 只允许显示一次（用 `sessionFlags[key]=true` 实现；不依赖时间）
- `installOnce`：本机安装周期只允许显示一次（用 `UserDefaults[key]=true` 实现）
- `stateOnly`：只在“进入状态”的那一刻显示一次（状态未解除期间不允许重复 emit；解除后再次进入状态可再次显示）

---

#### A.4 队列、优先级、抢占（必须严格一致）
##### A.4.1 槽位（Slot）
实现必须维护 4 个槽位：
- `slotToast`（承载 L1）
- `slotBanner`（承载 L2）
- `slotModal`（承载 L3）
- `slotViewerBlockingBar`（仅承载 viewerBlockingBarTop / write_failed）

##### A.4.2 不排队（硬规则）
提示系统**永不排队**。新提示无法显示时直接丢弃（除非满足抢占规则）。

##### A.4.3 抢占规则（deterministic）
当新 Prompt 到来：
1) 先执行 Gate 检查（A.5.1），Gate 不通过则丢弃
2) 执行 throttle 检查（A.5.2），不通过则丢弃
3) 根据 surface/level 映射到槽位
4) 若槽位为空 → 展示
5) 若槽位非空：
   - 新 `priority > 当前` → 立刻替换（旧的 dismissReason=preempt）
   - 新 `priority == 当前` → `emittedAt` 更晚者覆盖
   - 新 `priority < 当前` → 丢弃新提示

---

#### A.5 触发/展示算法（写代码只需要照这段实现）
##### A.5.1 Gate 检查（先于 throttle）
- `installOnce`：若 `UserDefaults[key]==true` 则丢弃；展示成功后立刻写入 `true`
- `sessionOnce`：若 `sessionFlags[key]==true` 则丢弃；展示成功后立刻写入 `true`
- `stateOnly`：仅当 `stateTransitions[key]` 从 `false→true` 的那一刻允许 emit；进入状态后保持 true；退出状态设回 false

##### A.5.2 Throttle 检查
- perKey：若 `now - lastShownAt[key] < perKeyMinIntervalSec` → 丢弃
- global：维护 `globalShownTimestamps`；移除 `now-globalWindowSec` 之前的记录；若剩余数量 ≥ globalMaxCountInWindow → 丢弃
- dismiss suppress：当用户关闭/取消（dismissReason=close 或 action=“取消/稍后”）时，设置 `suppressedUntil[key]=now+suppressAfterDismissSec`；若 `now < suppressedUntil[key]` → 丢弃

##### A.5.3 自动消失计时器
- L1/L2 自动消失时：创建 timer；到时 dismissReason=auto
- App 进入后台：暂停 timer；回前台继续（剩余时长续跑）
- L2/有按钮（autoDismiss=null）：不创建 timer

##### A.5.4 多事件同帧处理
同一 runloop 内触发多个 prompt：按 `priority desc` → `emittedAt desc` 逐个尝试写槽位；最终每槽位只保留 1 个。

---

#### A.6 边缘情况补齐（量化 & 不改变主文口径）
##### A.6.1 快门被 write_failed 阻断时的“解释入口”
若 `existsWriteFailed==true` 且用户停留在拍摄页（camera visible）：
- 必须展示 L2 Banner：`有未保存照片：先处理再继续拍`（key=`blocked_by_write_failed`，priority=95，带按钮 `去处理` 跳到第一个失败项的 Viewer）
- 该 Banner 不自动消失（有按钮）；用户关闭 × 后 60s 内不再出现（L2 suppress 默认）

> 目的：避免“快门灰了但用户不知道为什么/怎么解”。

##### A.6.2 低空间阈值（冻结）
- `DISK_WARN_MB = 500`
- `DISK_BLOCK_MB = 200`

**触发规则**
- 当 `freeMB < DISK_WARN_MB` 且本 Session 未提示过：emit `low_space_warn`（gate=sessionOnce）
- 当用户尝试以下动作且 `freeMB < DISK_BLOCK_MB`：emit `low_space_blocking`（gate=none；按 L3 suppress 30s）
  - 拼图保存 / 导出 / 分享
  - 参考图复制保存（把参考图写入 Just Photo 相册）
  - 导入照片到 Session（若会触发额外写入/缓存；否则可仅提示 warn）

**freeMB 计算口径（必须）**
- 使用 `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`（单位字节）转换为 MB（向下取整）。

##### A.6.3 购买/恢复购买的按钮数量（冻结）
- purchase_failed：3 按钮（重试/稍后/检查网络）
- restore_failed：2 按钮（重试/稍后）+ 第三按钮“管理订阅”（可作为 tertiary）

---

#### A.7 Prompt Catalog（唯一真相：所有提示必须来自这里）
> 实现要求：把下表转成代码内的 `PromptCatalog`（Swift 常量数组或 JSON 资源均可）。
> UI 渲染层不得写硬编码文案、不得写节流判断。

字段：
- `key, level, surface, priority, blocksShutter, gate`
- `autoDismiss`: `default` 或 `none`
- `throttle`: `perKey/globalWin/globalMax/suppress`
- `titleTemplate, messageTemplate`
- `primaryActionId/title, secondaryActionId/title, tertiaryActionId/title`

##### A.7.1 Catalog 表
| key | level | surface | priority | blocksShutter | gate | autoDismiss | throttle(perKey/globalWin/globalMax/suppress) | titleTemplate | messageTemplate | primary | secondary | tertiary |
|---|---|---|---:|---:|---|---|---|---|---|---|---|---|
| subject_lost | L2 | cameraBannerTop | 55 | false | stateOnly | none | 10/20/2/60 |  | 主角消失：请把她拉回画面 | resume_engine / 继续 |  |  |
| session_count_15 | L2 | cameraBannerTop | 40 | false | sessionOnce | default | 10/20/2/60 |  | 已拍 {count} 张：请挑选/清空 | open_filmstrip / 去挑选 |  |  |
| session_full_20 | L3 | cameraModalCenter | 80 | false | none | none | 10/60/1/30 | 本次已满 20 张 | 清理未喜欢，才能继续拍。不会删除系统相册照片。 | clear_unliked / 清理未喜欢 | dismiss / 取消 |  |
| camera_permission_denied | L3 | cameraModalCenter | 92 | false | none | none | 10/60/1/30 | 需要相机权限 | 打开系统设置允许相机，才能拍照。 | open_settings / 去设置 | dismiss / 取消 |  |
| camera_init_failed | L3 | cameraModalCenter | 90 | false | none | none | 10/60/1/30 | 相机初始化失败 | 点重试，或去设置检查相机/相册权限。 | retry_camera_init / 重试 | open_settings / 去设置 |  |
| reset_session_confirm | L3 | cameraModalCenter | 65 | false | none | none | 10/60/1/30 | 确认重置会话？ | 将清空：session photos、used、wrap、参考图列表。不删除：系统相册里的照片。 | reset_session / 确认重置 | dismiss / 取消 |  |
| capture_failed | L3 | cameraModalCenter | 85 | false | none | none | 10/60/1/30 | 没拍到 | 再按一次快门。 | retry_capture / 重试 | dismiss / 取消 |  |
| write_failed | L3 | viewerBlockingBarTop | 100 | true | none | none | 2/60/1/0 |  | 未保存到系统相册（{reason}） | retry_write / 重试保存 | abandon_item / 放弃此张 |  |
| blocked_by_write_failed | L2 | cameraBannerTop | 95 | false | none | none | 2/20/2/60 |  | 有未保存照片：先处理再继续拍 | open_first_write_failed / 去处理 |  |  |
| album_add_failed | L2 | cameraBannerTop | 60 | false | none | default | 10/20/2/60 |  | 已保存，但没进 Just Photo 相册 | retry_album_add / 修复 |  |  |
| thumb_failed | L2 | viewerBannerTop | 50 | false | none | default | 10/20/2/60 |  | 缩略生成失败，不影响原图 |  |  |  |
| viewer_load_failed | L2 | viewerBannerTop | 50 | false | none | default | 10/20/2/60 |  | 加载失败，可重试 | retry_viewer_load / 重试 |  |  |
| permission_upgrade_required | L3 | sheetModalCenter | 70 | false | none | none | 10/60/1/30 | 需要相册权限 | 你可以补选要授权的照片，或去系统设置改为完全访问。 | open_limited_picker / 管理已选照片 | open_settings / 去系统设置 |  |
| favorite_sync_failed | L2 | cameraBannerTop | 58 | false | sessionOnce | none | 10/20/2/60 |  | 已在 App 内标记喜欢，但没法同步到系统“喜欢”。 | open_settings / 去设置 |  |  |
| ref_first_save_notice | L3 | sheetModalCenter | 45 | false | installOnce | none | 10/60/1/30 | 提示 | 将把参考图保存到「Just Photo」相册，仅用于参考，可随时删除。 | dismiss / 知道了 |  |  |
| ref_reject_not_suitable | L3 | sheetModalCenter | 75 | false | none | none | 10/60/1/30 | 这张不适合做参考图 | 原因：{reason} | pick_ref_again / 换一张 | dismiss / 取消 |  |
| ref_copy_failed | L2 | sheetBannerTop | 60 | false | none | none | 10/20/2/60 |  | 参考图保存失败。请检查相册权限或空间。 | open_settings / 去设置 |  |  |
| odr_unavailable | L1 | cameraToastBottom | 10 | false | none | default | 2/10/3/0 |  | 网络不可用，先用关键词 |  |  |  |
| purchase_failed | L3 | sheetModalCenter | 78 | false | none | none | 10/60/1/30 | 无法完成购买 | 你可以重试，或稍后再试。 | retry_purchase / 重试 | dismiss / 稍后 | open_network_settings / 检查网络 |
| restore_failed | L3 | sheetModalCenter | 78 | false | none | none | 10/60/1/30 | 恢复失败 | 你可以重试，或稍后再试。 | retry_restore / 重试 | dismiss / 稍后 | open_manage_subscriptions / 管理订阅 |
| low_space_warn | L2 | cameraBannerTop | 42 | false | sessionOnce | default | 10/20/2/60 |  | 空间偏低（< {mb}MB）：建议先清理，避免保存失败 |  |  |  |
| low_space_blocking | L3 | sheetModalCenter | 88 | false | none | none | 10/60/1/30 | 空间不足 | 需要至少 {mb}MB 才能继续此操作。先清理空间再重试。 | open_storage_settings / 去清理 | dismiss / 取消 |  |

---

#### A.8 触发条件（Emit Rules：逐条量化）
> 这一节决定“什么时候 emit 哪个 key”。写代码只能按这里的 if 条件触发。

- `subject_lost`：当 `engine.pauseReason == subjectLost` 且 `cameraVisible==true`；状态进入时 emit（gate=stateOnly）；状态解除后可再次进入。
- `session_count_15`：当 `session.photoCount` 从 14 变为 15 的那一刻 emit（payload.count=15，gate=sessionOnce）。
- `session_full_20`：当 `session.photoCount == 20`（拍完第 20 张）立刻 emit；以及当 `session.photoCount >= 20` 且用户点击快门尝试拍第 21 张时再次 emit（受 L3 throttle/suppress 控制）。
- `camera_permission_denied`：进入拍摄页时若 `AVCaptureDevice.authorizationStatus(.video) != .authorized`，立刻 emit（并阻断拍摄逻辑）。
- `camera_init_failed`：当进入拍摄页后 `warmupElapsedSeconds > 8.0` 且 `cameraState != ready`。
- `reset_session_confirm`：用户点击“重置会话”按钮立即 emit。
- `capture_failed`：快门流程返回错误且未获得图像数据（真正没拍到）。
- `write_failed`：已获得图像数据，但写入系统相册失败；必须写入 `SessionItem.state = write_failed(reason)` 并 emit（payload.reason=WriteFailReason）。
- `blocked_by_write_failed`：当 `existsWriteFailed==true` 且 `cameraVisible==true` 且快门被禁用时 emit（用于解释入口）。
- `album_add_failed`：系统相册写入成功后，把 asset 归档进 “Just Photo” 相册失败时 emit。
- `thumb_failed`：对任意 `SessionItem`，若 `optimisticThumbShownAt + 5.0s` 仍未替换真实缩略图 → 标记该项 `thumb_failed`；当用户进入该项 Viewer 时 emit。
- `viewer_load_failed`：打开 Viewer 后 `3.0s` 内未出首帧且判定失败时 emit。
- `permission_upgrade_required`：用户执行需要更多相册可读权限的动作且当前权限不足时 emit（例如：导入/管理已选/需要读未授权照片）。
- `favorite_sync_failed`：用户点 ✅ liked 后，在 Full 权限下尝试同步系统 Favorite 失败时 emit（每 Session 只提示 1 次）。
- `ref_first_save_notice`：首次把参考图复制保存到 “Just Photo” 相册前 emit（gate=installOnce；用户点“知道了”后继续保存动作）。
- `ref_reject_not_suitable`：参考图强门槛任一命中时 emit（payload.reason=RefRejectReason）。
- `ref_copy_failed`：参考图复制保存失败时 emit。
- `odr_unavailable`：用户打开“没灵感”但网络不可用/ODR 拉取失败时 emit（不阻断）。
- `purchase_failed`：购买失败或无网时 emit（必须是 L3）。
- `restore_failed`：恢复购买失败或无网时 emit（必须是 L3）。
- `low_space_warn`：每次拍照前检查 `freeMB`；若 `< DISK_WARN_MB` 且本 Session 未提示过则 emit（payload.mb=DISK_WARN_MB）。
- `low_space_blocking`：用户尝试“拼图保存/导出/分享/参考图复制保存”等动作前检查 `freeMB`；若 `< DISK_BLOCK_MB` 则 emit（payload.mb=DISK_BLOCK_MB）并阻止该动作执行。

---

#### A.9 Action Library（按钮行为：必须照表实现）
> 所有 actionId 必须从这里选；禁止 UI 层写匿名闭包。

| actionId | 唯一效果（必须做到） |
|---|---|
| dismiss | 关闭当前 Prompt；对 L3 触发 suppressAfterDismiss；对 L2 点 × 也触发 suppress |
| resume_engine | 让引擎从 paused 恢复（继续评估/提示） |
| open_filmstrip | 展开胶卷条/抽屉并聚焦列表顶部 |
| clear_unliked | 从 session 工作集移除所有未✅项（不删除系统相册照片） |
| retry_camera_init | 重新初始化相机 session（销毁并重建 AVCaptureSession） |
| retry_capture | 重新执行一次拍照 capture |
| retry_write | 对当前 write_failed 项重新写入系统相册 |
| abandon_item | 从 session 工作集移除该项（因为未写入成功，不影响系统相册） |
| open_first_write_failed | 打开 Viewer，并定位到第一个 write_failed 项 |
| retry_album_add | 重新把该 asset 归档到 Just Photo 相册 |
| retry_viewer_load | Viewer 重载当前资源（重建渲染/重新读取资源） |
| open_limited_picker | 调系统 “Manage Limited Photos” 面板 |
| open_settings | 跳转到系统设置 App 的本 App 设置页 |
| pick_ref_again | 重新打开参考图选择（系统 Photos picker 或 ODR picker） |
| retry_purchase | 重新发起 StoreKit 购买 |
| retry_restore | 重新发起 StoreKit 恢复购买 |
| open_manage_subscriptions | 打开系统订阅管理页（App Store Subscriptions） |
| open_network_settings | 打开系统设置（Wi‑Fi/蜂窝不可深链时打开 Settings 根） |
| open_storage_settings | 打开系统设置（存储不可深链时打开 Settings 根并引导进入“通用-存储空间”） |
| reset_session | 执行重置会话（清空 session photos/used/wrap/refList 并回到 S0） |

---

#### A.10 reason 映射（必须一致）
##### A.10.1 write_failed reason → {reason}
- `no_permission` → `没拿到相册权限`
- `no_space` → `手机空间不够`
- `photo_lib_unavailable` → `系统相册暂时不可用`
- `system_pressure` → `系统太忙`

##### A.10.2 ref_reject_not_suitable reason → {reason}
- `multi_person` → `画面里有多个人`
- `face_too_small` → `脸太小`
- `eyes_not_visible` → `看不到眼睛`
- `upper_body_incomplete` → `上半身不全`

**括号规则（必须）**
- `write_failed` 的 message：若 `{reason}` 为空 → 显示 `未保存到系统相册`；若不为空 → `未保存到系统相册（原因）`

---

#### A.11 快门阻断规则（必须实现，不允许例外）
- 当且仅当 session 中存在任意 `write_failed` 项：
  - 快门按钮 `disabled=true`
  - 任何拍照请求直接返回（不触发 capture，不产生新 item）
- 解除条件：
  - `retry_write` 成功 → 该项转为 `write_success`（并继续 album_add）
  - 或 `abandon_item` → 从 session 工作集移除

---

#### A.12 统一埋点（建议实现；字段固定）
事件名固定：
- `prompt_shown`
- `prompt_dismissed`（含 dismissReason：auto/close/action/preempt）
- `prompt_action_tapped`

必带字段：
- `key, level, surface, priority, blocksShutter, emittedAt`
- `payload`（仅透传，不参与逻辑）

---

#### A.13 本地诊断日志（Local Diagnostics Log）格式（冻结：必须可导出/可复现）

目的：让 QA/开发在**不接入任何远端 SDK**的前提下，对“无提示但不达标 / 回退原因 / 写入异常 / Limited 幻影资源”等问题**可复现、可追溯**。

**文件与轮转（冻结）**
- 存储：App Sandbox（用户可通过设置页导出）。
- 形式：JSON Lines（每行 1 条记录），UTF-8。
- 轮转：总大小上限 **50MB**；或最久 **30 天**（先到为准）→ 超限按“最旧优先”滚动删除。

**记录结构（每行必须包含；字段缺失视为不合格实现）**
- `ts_ms: Int64`：Unix epoch 毫秒
- `session_id: String`：本地随机，见 9.2
- `event: String`：事件名（见下）
- `scene: String`：`cafe|outdoor`
- `payload: Object`：事件载荷（仅本地，不上报）

**必须实现的事件与 payload（最小集合，冻结）**
1) `withref_match_state`
   - `payload.match: Bool`
   - `payload.required_dimensions: [String]`（维度 ID，见 5.1.1.a）
   - `payload.blocked_by: [String]`（当 match=false 且 UI 安静时必须非空；= `match_blocked_by`）
2) `withref_fallback`
   - `payload.reason: String`（= `withRefFallbackReason`，枚举见 5.1.2）
   - `payload.missing: [String]?`（缺失 ROI/landmarks 名称，可选）
3) `photo_write_verification`
   - `payload.assetIdHash: String`
   - `payload.first_fetch_ms: Int`（从 write_success 回调到首次 fetch 的耗时）
   - `payload.retry_used: Bool`
   - `payload.retry_delay_ms: Int?`（固定 500）
   - `payload.verified_within_2s: Bool`
4) `phantom_asset_detected`
   - `payload.assetIdHash: String`
   - `payload.auth_snapshot: {status:String, scope:String}`（最小字段即可）
5) `odr_auto_retry`
   - `payload.state_before: String`（必须为 failed_retry）
   - `payload.debounce_ms: Int`（固定 500）
   - `payload.result: String`（success|fail|skipped_left_page）

**验收口径（冻结）**
- Given：UI 安静但 Match=false → Then：必须出现 `withref_match_state` 且 `blocked_by` 非空。
- Given：Limited 幻影资源 → Then：必须出现 `phantom_asset_detected`，且 UI 不中断。
- Given：write_success 后首次 fetch nil 但 500ms 后成功 → Then：`photo_write_verification.retry_used=true` 且 `verified_within_2s=true`。


### 附录 B｜Session 定义

> 本附录定义的 **Session（业务会话）** = 用户“本次拍摄任务”的工作集（filmstrip/Viewer/Wrap 的来源），**不等于** AVFoundation 的 `AVCaptureSession`（相机采集会话）。
> 目标：即使开发者完全不了解业务背景，只要照本附录实现，就能得到**可验收、可恢复、边缘情况可控**的 Session 行为。

---

#### B.0 术语与核心不变量（必须一致）

**术语**
- **Session（业务会话）**：用户从进入相机页开始，到用户执行 `reset_session`（重置会话）为止的一段“拍摄任务”。
- **Workset（工作集）**：本 Session 的照片条目列表，驱动 filmstrip/Viewer。上限 20。
- **SessionItem（条目）**：Workset 中的每一张“本次拍摄结果”的记录（可能已写入系统相册，也可能写入失败等待重试）。
- **Optimistic 缩略**：按快门后立刻插入一条 `captured_preview` 占位项，后续由真实缩略替换（详见正文 6.1 / 附录 C）。

**不变量（硬规则）**
1) Workset 的展示顺序永远：**最新在前（desc）**（Viewer 顺序必须与 filmstrip 完全一致）。
2) Workset 计数口径 `workset_count`：**等于 workset 数组长度**，包含状态：`captured_preview / writing / thumb_ready / thumb_failed / write_failed`；`capture_failed` 永不入列。
3) 任意时刻：**存在任意 `write_failed`** → **全局阻断快门**（A.11）。
4) 清理/重置只影响 Workset（App 内列表），**不删除系统相册原片**（正文 4.1.3）。
5) 任何写入系统相册的请求都必须可“断点恢复”：发生前后台切换/来电/杀进程时，不能出现“用户拍到了但完全找不到”的灾难。

---

#### B.1 数据结构（可直接照此落库/落文件）

> 推荐实现：一个本地 `SessionStore`（JSON 或 SQLite 均可），外加 `SessionCache`（缩略/待写入原始文件）。
> 必须保证：**杀进程后可恢复 workset 与 write_failed 的“重试/放弃”**。

##### B.1.1 Session（业务会话）结构

字段（必须有）：
- `sessionId: String`：本地随机 UUID，创建后不变（用于埋点 `session_id`）。
- `createdAt: UnixMs`
- `lastActiveAt: UnixMs`：任何会话变更都刷新（拍照插入/状态变更/✅/清理/重置/参考图增删/Wrap 变化）。
- `scene: enum {cafe, outdoor}`（与 PRD 主体一致）
- `mode: enum {shooter}`（MVP 固定）
- `workset: [SessionItem]`：最新在前
- `sessionFlags: { [String]: Bool }`：用于 `sessionOnce` Gate（见 A.3.3/A.5）
- `used: { ... }`：正文已定义的“已用集合”（若有）
- `wrap: { ... }`：收工/拼图状态（若有）
- `refList: [RefItem]`：参考图列表（若有）

##### B.1.2 SessionItem 结构（必须有字段）

> `itemId` 必须稳定（杀进程后仍能定位），建议 UUID。

- `itemId: String`
- `shotSeq: Int`：从 1 开始递增；**只增不减**（用于埋点/调试稳定序号，避免清理后 index 变化导致歧义）
- `createdAt: UnixMs`
- `state: enum`
  - `captured_preview`
  - `writing`
  - `write_success(assetId: String)`
  - `write_failed(reason: enum)`（reason 枚举见 A.10）
  - `album_add_success` / `album_add_failed(reason?: enum)`（如正文已定义）
  - `thumb_ready`
  - `thumb_failed`
- `liked: Bool`：默认 `false`；✅ 切换此值（并在 Full 权限下“尝试”同步系统 Favorite，失败不阻断）
- `pendingFileRelPath?: String`：仅当 state ∈ {captured_preview, writing, write_failed} 且已拿到图像数据时存在，用于杀进程后重试写入系统相册（见 B.3）。
- `thumbCacheRelPath?: String`：真实缩略缓存（可选）；若无则按需从 Photos 生成。
- `lastErrorAt?: UnixMs`
- `assetId?: String`：仅当已 `write_success` 后存在（与 state 冗余允许，但必须一致）

**允许的“临时空档”（唯一例外）**
- `captured_preview` 刚插入时，可能还没拿到 photo data，因此 `pendingFileRelPath` 允许暂时为空；但必须在 **2.0s 内**要么补齐 pendingFile、要么进入 `capture_failed` 并移除该 item（见 B.3.2）。

---

#### B.2 Session 生命周期：开始/延续/结束（必须量化）

##### B.2.1 创建（Session Start）

触发（任一即创建新 Session）：
1) App 冷启动进入相机页时，且本地不存在“可恢复 Session”；或可恢复但已过期（见 B.3.4 TTL）。
2) 用户执行 `reset_session` 并确认（正文 7.6；A.9 actionId）。

创建动作（必须按顺序）：
- 生成 `sessionId`、清空 `workset/sessionFlags/used/wrap/refList`，进入 **S0**（首次拍照前：无胶卷条）。
- `lastActiveAt = now`
- 持久化（见 B.3.1：必须落盘成功才算创建完成）。

##### B.2.2 延续（Session Continue）

Session 在以下行为中**不结束**，仅更新 `lastActiveAt`：
- 前后台切换/来电打断/相机被占用等中断恢复
- 翻转前后摄（正文 7.1.3）
- 进入 Viewer / Wrap / Settings 再返回
- 清理未喜欢（clear_unliked）
- 选择/切换参考图

##### B.2.3 结束（Session End）

只有以下触发会结束并创建新 Session：
- `reset_session` 被确认执行
-（可选）自动过期：上次活跃超过 TTL（见 B.3.4），下次启动/回前台时创建新 Session

---

#### B.3 持久化策略（杀进程可恢复的最小实现）

> 本策略参考 Apple 官方示例 AVCam 的“后台保存/中断恢复”思路，以及 iOS 对相机后台不可用与中断通知的规则。

##### B.3.1 存储位置与文件组织（建议但可验收）

- `Application Support/SessionStore/`
  - `current_session.json`（或 SQLite DB）
  - `pending/`（最多 2 个文件；用于“已拍到但未写入系统相册”的断点恢复）
- `Library/Caches/SessionCache/`
  - `thumb/`（缩略缓存；可被系统清理，不影响数据安全）

硬要求：
- `current_session` 必须在**每次会话变更**后最终落盘（可 debounce 200ms），但在以下事件必须**立即同步落盘**：
  - `willResignActive` / `didEnterBackground`
  - `applicationWillTerminate`（若有机会）
  - 任一 `write_failed` 发生时（避免杀进程后丢失失败项）

##### B.3.2 拍照插入与 pendingFile 生成（保证“拍到了不丢”）

当用户点快门：
1) 立刻插入 `SessionItem(state=captured_preview, liked=false)` 到 workset 头部；`shotSeq++`；刷新 `lastActiveAt`；落盘（可异步，但必须在 200ms 内触发写入）。
2) 当拿到 photo data（`AVCapturePhotoOutput` 回调）后，**先把原始数据写入** `Application Support/.../pending/<itemId>.heic`（原子写入：写 tmp → rename）。
3) 写入 pendingFile 成功后，立刻把 item.state 置为 `writing`，并开始 `PHPhotoLibrary.performChanges` 写入系统相册。
4) 若回调后 **2.0s 内仍未拿到 photo data**（极端中断/权限变化），必须将该 item 从 workset 移除，并触发 `capture_failed` 逻辑（正文 6.1.2）。

##### B.3.3 前后台/来电时的“后台保存”策略（必须实现）

当 App 进入后台或变为 inactive（如来电）：
- 如果存在任意 item.state ∈ {`writing`}（正在写系统相册）：
  1) 立即调用 `UIApplication.beginBackgroundTask(withName:)` 申请**额外后台时间**，确保 `PHPhotoLibrary` 的 completion handler 有机会返回。
  2) 在 background task 的 expiration handler 中：
     - 将所有仍处于 `writing` 的 item 强制置为 `write_failed(reason=photo_lib_unavailable)`；
     - 保留其 `pendingFileRelPath` 以便回前台/下次启动 `retry_write`；
     - 立即落盘 `current_session`。
  3) 写入完成后（成功/失败回调）必须 `endBackgroundTask`（否则可能被系统终止）。
- 无 in-flight 写入时：允许停止 `AVCaptureSession`（节电/热），回前台再恢复（见 B.4）。

##### B.3.4 Session 恢复 TTL（必须量化）

- `SESSION_RESTORE_TTL = 12h`（从 `lastActiveAt` 起算）
- App 冷启动/从后台恢复时：
  - 若存在 `current_session` 且 `now - lastActiveAt <= TTL` → 尝试恢复
  - 否则：丢弃旧 session（删除 current_session + cache），创建新 session（见 B.2.1）

##### B.3.5 冷启动恢复流程（必须 deterministic）

启动时按以下顺序执行（不允许省略）：
1) 读取 `current_session`（JSON/DB）；若解析失败 → 视为无 session，创建新 session。
2) **Workset 校验**（逐条）：
   - 若 state 为 `write_success` / `thumb_*` / `album_add_*`：
     - 用 `assetId` 校验 Photos 中是否仍存在该资源；若不存在（用户在系统相册删除）→ 从 workset 移除，并计数 `removed_by_external_delete++`。
   - 若 state 为 `write_failed`：
     - 若 `pendingFile` 存在 → 保留，可 `retry_write` / `abandon_item`
     - 若 `pendingFile` 不存在 → 自动 `abandon_item`（从 workset 移除），并计数 `removed_missing_pending++`
   - 若 state 为 `writing`：
     - 一律转为 `write_failed(reason=photo_lib_unavailable)`（因为 completion 不可再依赖），并保留 pendingFile（若有）
   - 若 state 为 `captured_preview` 且没有 pendingFile：
     - 直接移除（视为未完成拍摄）
3) 若 `removed_by_external_delete + removed_missing_pending > 0`：
   - 展示一次 L2 Banner：`有 X 张照片已不可用，已从本次列表移除`（Gate=sessionOnce，key=`session_recover_prune`）。
4) 恢复完成后：根据 workset 是否为空决定状态：
   - workset 为空 → 进入 S0（无胶卷条）
   - workset 非空 → 进入 S1（有胶卷条）

---

#### B.4 生命周期与中断处理（前后台/来电/旋转/杀进程）

> 参考 Apple 的“App life cycle”与 AVFoundation 中断通知与原因枚举。

##### B.4.1 App/Scene 状态 → 行为矩阵（必须照表实现）

| 事件 | 必须动作（顺序） | 快门 | 相机采集（AVCaptureSession） | 引擎（提示/评估） |
|---|---|---|---|---|
| 进入 `active`（回前台/解锁） | 1) 恢复/创建 Session（B.3.5） 2) 重建/启动相机采集 3) 若有 `write_failed` → 保持全局阻断（A.11） | 允许（除非被 A.11/A.4 in-flight/20上限阻断） | `startRunning()`；ready 后隐藏 warmup | `resume_engine` |
| 进入 `inactive`（来电/控制中心/系统弹窗） | 1) 立刻暂停引擎 2) 禁止新拍照 3) 若 in-flight 写入存在 → 执行 B.3.3 后台保存 | disabled | 可继续 running（允许保持预览）；但不允许发起新 capture | `paused` |
| 进入 `background` | 1) 立即落盘 current_session 2) 若 in-flight 写入存在 → B.3.3 申请 background task 3) 否则 0.5s 内停止 `AVCaptureSession` | disabled | `stopRunning()`（无 in-flight 时） | `paused` |
| 被系统终止（kill/崩溃） | 无回调保障；依赖 B.3 的落盘与 pendingFile | - | - | - |

##### B.4.2 AVCaptureSession 中断（必须处理）

监听并处理：
- `AVCaptureSession.wasInterruptedNotification`：读取 `InterruptionReason`。
- `AVCaptureSession.interruptionEndedNotification`：尝试恢复。

规则（硬）：
1) 收到 wasInterrupted：
   - 立刻禁用快门（UI 显示 warmup/占用态）
   - reason == `videoDeviceNotAvailableInBackground`：按“进入后台”处理（B.4.1）
   - 其他 reason（如被别的 app 占用）：显示 L2 Banner：`相机被占用，稍后会自动恢复`（无按钮）
2) interruptionEnded：
   - 重新 `startRunning()` 并进入 warmup
   - 若 **8.0s** 内仍未 ready：触发正文的“相机初始化失败（camera_init_failure）”L3 Modal（重试/去设置/取消）

##### B.4.3 旋转（Rotation）处理（必须确定）

MVP 建议：**强制竖屏**（UI 不支持横屏）。
若仍收到方向变化（iPad/系统旋转锁未开）：
- 不创建新 Session、不清空 workset
- 仅执行 UI 层重布局：
  - 参考图 overlay：保持“相对预览层”的归一化坐标不变，重新计算 pixel frame 并 clamp（正文已有 clamp 规则）
  - Viewer：保持当前 `itemId`；若 scale>1，保持当前缩放/平移（以新 viewport 重新 clamp 边界）
- 旋转过程禁用快门（防止布局跳变时误触），**300ms** 后恢复（除非其他阻断条件存在）

##### B.4.4 权限变化与资源不可访问（必须兜底）

**场景**：用户在系统设置里把 Photos 权限从 Full/Limited 改为 Denied，或把某些照片从“已授权集合”移出，导致 `assetId` 变得不可读。

规则（硬）：
1) 每次进入 `active` 时都要重新读取当前 Photos 授权范围（Full/Limited/Denied）。  
2) 对于 workset 中 `write_success(assetId)` 的条目：若 `PHAsset.fetchAssets(withLocalIdentifiers:)` 返回空（不可访问/已删除），该条目不得导致崩溃。
2.1) 若出现“已授权但 fetch 为空”的情况（常见于 Limited 历史授权 + 用户在系统相册删除/移出授权）：必须写入本地诊断日志 `phantom_asset_detected`（含 authSnapshot、assetIdHash），用于排查权限/删除导致的不可读状态；UI 仍按本节兜底显示，不阻断主流程。  
3) UI 兜底（必须）：
   - filmstrip：显示灰底占位 + 角标 `!`；点按进入 Viewer
   - Viewer 顶部显示提示：`无法读取照片，请授权访问`，按钮：`管理已选照片`（Limited 时）/`去系统设置`（Denied 时）
4) 计数口径不变：不可读条目仍计入 workset_count（因为它仍是“本次列表”的一部分），除非用户选择 `reset_session` 或手动清理/放弃。

##### B.4.5 内存压力（Memory Warning）兜底（必须）

- 收到系统内存警告时：必须立刻释放内存中的缩略图缓存（UIImage/CGImage），但不得丢失 `current_session` 落盘数据。  
- 允许：缩略图回退为占位并延迟重建；不允许：workset 丢失、✅ 状态丢失、write_failed 丢失。


---

#### B.5 清理未喜欢（clear_unliked）：对 UI/计数/Viewer 落点的确定规则

> 行为入口：正文 4.1.3 的 20 张 L3 Modal 按钮 & A.9 actionId=`clear_unliked`。

##### B.5.1 清理口径（谁会被清）

- 被清理的条目集合 `toRemove`：所有 `liked == false` 的 SessionItem，且 **state ∉ {writing, write_failed}**。
- `writing` 不允许被清理（因为写入进行中，避免状态悬空）。
- `write_failed` 不允许被清理（必须由用户在失败项上执行 `retry_write` 或 `abandon_item`，否则会造成“未保存但悄悄消失”的数据安全问题）。
- 若存在任意 `write_failed`：由于 A.11 已阻断快门，清理未喜欢仍允许执行，但必须遵守 B.5.3 的落点规则。

##### B.5.2 清理动作（必须按顺序）

1) 计算 `toRemoveCount`；若为 0：直接 dismiss 当前弹窗并给 L1 Toast：`没有可清理的`。
2) 从 workset 中移除这些 item（不触发任何删除系统相册行为）。
3) 同步清理缓存：
   - 删除 `thumbCache`（若存在）
   - 若被移除条目拥有 `pendingFile`：一律删除（这些条目不是 write_failed，因此不存在“重试保存”的需求）
4) 重新计算 `workset_count`，并立刻刷新 UI（filmstrip/Viewer/计数/快门可点性）。
5) 立即落盘 `current_session`（不得 debounce）。

##### B.5.3 Viewer 落点规则（最容易做错，必须 deterministic）

当清理发生时：
- 如果 Viewer **未打开**：只更新 filmstrip 和计数，无额外动作。
- 如果 Viewer **已打开**，并且当前正在展示 `currentItemId`：
  - 若 `currentItemId` 仍在 workset：Viewer 保持显示该 item（不跳）。
  - 若 `currentItemId` 被移除：
    1) 令清理前 Viewer 的索引为 `oldIndex`（0 = 最新）。
    2) 清理后：
       - 若 `newCount == 0`：自动关闭 Viewer → 回到相机页并进入 S0（无胶卷条）。
       - 否则：新的落点索引 `newIndex = min(oldIndex, newCount - 1)`，跳转到该索引对应的 item（等价于“尽量留在原位置，超界就落到最后一张”）。
- 任何跳转后：Viewer 的缩放状态重置为 `scale=1`（避免在不同图片上沿用平移/缩放导致越界）。

##### B.5.4 对 20 上限/15 强提醒的影响（必须明确）

- 清理后若 `workset_count < 20`：快门立即恢复可点（除非 A.11 write_failed 或 in-flight==2 阻断）。
- 15 强提醒（14→15 跨越）属于 `sessionOnce`：即使清理降回 <15，后续再次跨越 **也不再弹**（见 4.1.2/4.1.3）。

---

#### B.6 清理与回收（防止缓存爆炸）

- `reset_session`：必须删除 `current_session` 文件 + 清空 `SessionCache/thumb` + 删除 `pending/` 下所有文件。
- App 启动时的自动清理：
  - 删除 `thumb` 缓存中 `mtime > 7d` 的文件（允许全删）
  - 删除 `pending` 中 `mtime > 24h` 的文件；对应 item 若仍在 workset，则在恢复流程中会被自动移除（B.3.5）

---

#### B.7 必测用例（照这个测就能验收）

1) **后台 + 来电**：按快门进入 `writing` → 立刻按电源锁屏/来电 → 回来后：
   - 若保存成功：条目变 `write_success` 且可进 Viewer；pendingFile 被删除
   - 若保存失败：条目为 `write_failed`，快门阻断；可 `retry_write` / `abandon_item`
2) **杀进程恢复**：存在 `write_failed`（且 pendingFile 在）→ 杀进程 → 重启：
   - workset 恢复，失败项仍在且可重试；快门仍阻断直至处理
3) **外部删除**：系统相册删除某张本 Session 的 asset → 回到 App：
   - 该条目自动从 workset 移除，并弹一次 Banner 提示（B.3.5）
4) **清理未喜欢（Viewer 落点）**：打开 Viewer 停在某张未✅ → 执行清理未喜欢：
   - Viewer 自动跳到规则定义的落点；计数正确；快门按上限规则恢复
5) **旋转**：iPad 旋转设备 → UI 重布局不丢 session；快门 300ms 内禁用后恢复；参考图 overlay 位置不乱跳

### 附录 C｜保存管线状态机（Optimistic thumb / 失败 / 重试）

> 目标：**把 6.1.1 的“最小冻结版”落成可写代码的确定性规格**：状态机细节、错误码映射、重试策略与 UI 合约。  
> 核心验收：把你自己当成“完全不懂业务背景、只能死板执行指令的初级 AI 程序员”，仅凭本附录 + 6.1.1/6.1.3/Prompt Catalog，你应当无需追问即可实现。

---

## C.0 术语与总览（必须一致）

### C.0.1 三条流水线（Pipeline）
对每张 `SessionItem`，保存相关流程由 3 条相互独立但有顺序依赖的流水线组成：

1) **Write（写入系统相册）**：把拍摄得到的原始媒体写入系统相册并得到 `assetId`（失败→`write_failed`，并**全局阻断快门**）。
2) **Album Add（归档进 Just Photo 相册）**：在 `write_success(assetId)` 之后，尽力把该 `assetId` 加入 `Just Photo` 专属相册（失败→`album_add_failed`，**不阻断快门**）。
3) **Thumb（缩略图生成/替换）**：在 `captured_preview` 之后立刻显示 **Optimistic thumb**（预览帧/占位图），随后尽快生成“真实缩略图”并替换（超过 5.0s→`thumb_failed`，可自愈，见 6.1.1）。

### C.0.2 Optimistic thumb 的定义（冻结）
- **Optimistic thumb**：快门瞬间从相机预览流抓取的“最后一帧”或“近似帧”，用于立刻填充 filmstrip（用户立刻看见“拍到了”）。
- **真实缩略图**：由“拍摄得到的原始媒体”生成的缩略图（优先来自 `pending file` 本地生成；若本地不可用则可降级从系统相册按 `assetId` 请求）。
- **替换**：真实缩略图准备好后，必须**原地替换** Optimistic thumb（同一 `SessionItem.itemId` 不变）。

---

## C.1 必备数据结构（实现方不得自造字段语义）

> 说明：下述字段若在附录 B 已存在，必须沿用；若附录 B 未显式定义但本附录要求，允许以“扩展字段”落地（但语义必须一致）。

### C.1.1 SessionItem 扩展字段（Save Pipeline 需要）
每个 `SessionItem` 必须至少具备以下字段（含扩展字段）：

- `itemId: String`（唯一；用于文件名、缓存 key、重试定位；与附录 B 的 `itemId` 同名同义）
- `createdAtMs: Int64`
- `state: SessionItemState`（见 6.1.1；实现可内部拆分为 write/thumb/album 三个子状态，但对外表现必须与下述一致）
- `pendingFileRelPath?: String`（见附录 B；写入系统相册前用于承载原始媒体；write_failed 必须可用来重试）
- `assetId?: String`（write_success 后必须存在）
- `optimisticThumbShownAtMs?: Int64`（首次将 optimistic thumb 渲染到 UI 的时间点；用于 5.0s/30.0s 计时）
- `thumbCacheRelPath?: String`（当前用于 UI 展示的 thumb 文件：可先指向 optimistic，再被真实缩略替换）
- `writeAttemptCount: Int`（扩展字段；含自动重试；用于日志与节流；初始 0）
- `lastWriteError?: SaveErrorSnapshot`（扩展字段；用于错误映射与复现）
- `albumAttemptCount: Int`（扩展字段；含自动重试；初始 0）
- `lastAlbumError?: SaveErrorSnapshot`（扩展字段）
- `thumbAttemptCount: Int`（扩展字段；初始 0）
- `lastThumbError?: SaveErrorSnapshot`（扩展字段）

### C.1.2 SaveErrorSnapshot（错误快照结构）
`SaveErrorSnapshot` 不是给 UI 用的，是给：
- 错误映射（reason 的确定性选择）
- Debug（可回放）
- QA 验收（可检查“映射是否按规则”）

字段（全部必须可序列化存盘）：
- `stage: SaveStage`：`write | album_add | thumb`
- `errorDomain: String`（系统错误 domain；若无则填 `"(none)"`）
- `errorCode: Int`（系统错误 code；若无则填 0）
- `errorDesc: String`（系统 error.localizedDescription 的截断版；最多 200 字）
- `underlyingDomain?: String`（若可取到 underlying error，则记录其 domain）
- `underlyingCode?: Int`
- `freeMB: Int`（发生错误时的 freeMB；计算口径见 A.6.2）
- `photoAuthAtError: PhotoAuthSnapshot`（发生错误时相册权限快照；见 C.3.1）
- `tsMs: Int64`

---

## C.2 全局门控（Global Gates：阻断快门的唯一来源）

### C.2.1 in-flight 上限（复述冻结，补细节）
沿用 6.1.3：最多 2 个 in-flight（`captured_preview` 或 `writing`）。

补充“确定性计数口径”：
- `in_flight_count = count(items where state in {captured_preview, writing})`
- 当 `in_flight_count >= 2`：快门 disabled；展示 L2 Banner “保存中…”（无按钮）；当 `<2` 自动消失并恢复快门。

### C.2.2 write_failed 全局阻断（复述冻结，补细节）
- 若存在任意 `state == write_failed(*)`：
  - 快门 **必须 disabled**
  - 相机页必须 emit `blocked_by_write_failed`（A.8 已定义触发条件）
  - 直到失败项被用户处理为止（`retry_write` 成功 → `write_success`；或 `abandon_item` → 从 workset 移除）

> 注意：这条规则的优先级高于 “session_full_20”。即使 workset_count < 20，只要存在 write_failed，快门仍然禁用。

---

## C.3 Write 流水线：状态机与时序（可直接写成实现）

### C.3.1 PhotoAuthSnapshot（相册权限快照）
为保证错误映射可复现，发生写入动作与失败时必须记录：
- `status`: `not_determined | authorized | limited | denied | restricted`
- `canAddOnly`: Bool（若系统提供 add-only 许可态，记录当前是否处于“只写不读”的许可；默认 false）
- `isLimited`: Bool（status==limited 时为 true）

> 注：本 PRD 的“可实现口径 B：接受 Limited Access”要求：可读范围=“用户允许的那部分 + 我们新写入的”。因此只要 `status in {authorized, limited}`，就视为“具备写入资格”；其余都映射为 `no_permission`（见 C.4）。

### C.3.2 Write 状态机（单条 SessionItem）
用“状态 + 事件 + 约束”描述（实现必须严格遵守）：

#### (1) captured_preview（进入条件与动作）
进入条件：
- 用户点击快门并且 capture pipeline 成功进入“已触发拍照”阶段。

进入动作（必须在 **120ms** 内完成）：
- 生成/抓取 optimistic thumb，并立刻插入 filmstrip 新条目：
  - `state = captured_preview`
  - `optimisticThumbShownAtMs = nowMs`（第一次渲染时写入；不能只在“插入模型”时写）
  - `thumbCacheRelPath` 指向 optimistic thumb（若暂未落盘，允许先为空，但**必须在 500ms 内落盘并回填路径**）
- `writeAttemptCount` 不变（仍为 0）
- 启动 `CAPTURE_DATA_DEADLINE = 2.0s` 定时器：若 2.0s 内未收到“原始媒体数据可用”，则走 `capture_failed`（见 6.1.2）

#### (2) writing（进入条件与动作）
进入条件：
- 已收到原始媒体数据（例如 JPEG/HEIC/ProRAW/视频帧，具体由相机实现决定），并已成功写入 `pending file`（附录 B 的 pendingFileRelPath）。

进入动作（必须）：
- `state = writing`
- `pendingFileRelPath` **必须非空**（否则不得进入 writing）
- 立刻开始 Write Attempt #1（或 #N，见重试）：
  - 记录 `writeAttemptCount += 1`
  - 记录 `photoAuthSnapshot`（见 C.3.1）
  - 记录 `freeMB`（A.6.2）
- 启动 `WRITE_CALLBACK_TIMEOUT = 12.0s`：若超时仍未回调成功/失败，视为失败（映射 `photo_lib_unavailable`）

#### (3) write_success(assetId)（进入条件与动作）
进入条件：
- 系统相册写入回调成功，并返回可用 `assetId`（localIdentifier）。

进入动作（必须在回调后的 **200ms** 内完成）：
- `state = write_success(assetId)`
- `assetId` 持久化落盘（会话恢复需要）

- Post-Write Verification（冻结）：回调成功后必须尝试用 `assetId` fetch `PHAsset` 以验证“可读索引已生效”：
  - 若首次 fetch 返回空：允许在 **500ms** 后重试 1 次（总窗口 ≤ **2.0s**）。
  - 在上述验证窗口内 **不得** 将 item 从 `write_success` 降级为 `write_failed`（避免“保存成功却被误报失败”）。
  - 若超过 2.0s 仍 fetch 为空：必须记录本地日志 `post_write_verification_delayed`，并继续保持 `write_success(assetId)`；后续 Thumb/Viewer/AlbumAdd 允许延迟重试直至可读。
- 触发后续：
  - 启动 Album Add（C.5）
  - 启动 Thumb（C.6）
- `pending file` 的删除策略：见 C.8（不得立即删导致“thumb/Viewer 无源可读”）

#### (4) write_failed(reason)（进入条件与动作）
进入条件：
- 写入回调失败，或触发 `WRITE_CALLBACK_TIMEOUT`。

进入动作（必须在失败判定后的 **200ms** 内完成）：
- `state = write_failed(reason)`（reason 映射规则见 C.4）
- `lastWriteError` 记录为 `SaveErrorSnapshot(stage=write, ...)`
- 立即 emit `write_failed`（Viewer 阻断条；A.8 已定义）
- 立即触发“全局阻断快门”（C.2.2）

硬要求：
- `write_failed` 时，`pendingFileRelPath` **必须仍存在**（除非用户已手动放弃，或满足 C.8 的“过期清理”规则）。否则无法实现“可重试”。

---

## C.4 错误码映射（系统错误 → WriteFailReason → UI reason 字符串）

> 目的：把“失败原因”从模糊描述变成确定性函数，避免实现者随意写。

### C.4.1 内部枚举（冻结）
沿用 Appendix A 的 `WriteFailReason`（唯一允许的 4 类）：
- `no_permission`
- `no_space`
- `photo_lib_unavailable`
- `system_pressure`

同时定义**必须用于 UI 的中文短语**（写进 Prompt 的 `{reason}`）：
- `no_permission` → `权限不足`
- `no_space` → `空间不足`
- `photo_lib_unavailable` → `系统相册不可用`
- `system_pressure` → `系统繁忙`

> 注：Prompt Catalog 的 `write_failed` 文案为“未保存到系统相册（{reason}）”。实现必须传入以上中文短语，而不是 enum rawValue。

### C.4.2 映射算法（确定性优先级）
给定：
- 当前 `photoAuthSnapshot`
- 当前 `freeMB`
- `NSError`（含 domain/code/underlying）
输出：`WriteFailReason`

按以下顺序匹配（命中即返回，不再向下）：

1) **权限不足（no_permission）**
   - 若 `photoAuthSnapshot.status in {denied, restricted, not_determined}` → `no_permission`
   - 或系统错误 domain/code 明确表示 access denied（例如 `PHPhotosErrorDomain` 的 `accessUserDenied` / `PHPhotosErrorDomain 3310/3311（AccessRestricted/AccessUserDenied）` 等常见模式）

2) **空间不足（no_space）**
   - 若 `freeMB < DISK_BLOCK_MB(=200)`（A.6.2）→ `no_space`
   - 或系统错误显示“out of space/磁盘已满”类错误（常见为 `PHPhotosErrorDomain 3305` 或 `NSCocoaErrorDomain` 的写入空间不足）

3) **系统相册不可用（photo_lib_unavailable）**
   - 若系统错误来自 Photos 库不可用/未挂载卷（`PHPhotosError.Code.*` 中存在“库不可用/卷未挂载”的语义）
   - 或发生 `WRITE_CALLBACK_TIMEOUT`（12.0s 超时）→ `photo_lib_unavailable`

4) **系统压力/资源校验失败/未知（system_pressure）**
   - 兜底：全部剩余情况 → `system_pressure`
   - 典型案例：`PHPhotosErrorDomain 3302 invalidResource`（媒体资源校验失败/文件不合法/编码不受支持等）

### C.4.3 资源校验失败（3302）专项约束（避免“偶现”）
当命中类似 `invalidResource`（如 `PHPhotosErrorDomain 3302`）时，实现必须额外做一次“可复现校验”，以减少偶现：

- `pending file` 必须有**正确文件扩展名**（例如 .jpg/.heic/.mov），且扩展名必须与实际写入格式一致（否则可能触发 invalidResource）
- 写入系统相册前，`pending file` 必须仍存在且可读（避免被临时清理/提前删除）
- 若媒体为视频：必须确保音视频编码被 iOS 支持；不支持的音频 codec 也可能导致保存失败（外部案例）

---

### C.4.4 真实案例映射（用于 QA 复现/客服诊断；不作为逻辑分支）
> 目的：把“常见外部现象”落到**可复现测试**与**可读诊断**。实现不得在此处新增逻辑分支；逻辑仍以 C.4.2 的映射规则为准。

- **案例 1｜`PHPhotosErrorDomain 3302 (invalidResource)`**
  - 现象：保存视频/实况/某些下载视频时失败；重试通常无效。
  - 常见成因：视频包含 iOS 不支持的音频/视频 codec（例如 HEVC/x265 变体、非常见音频轨），或文件扩展名与实际编码不一致。
  - 验收复现建议：准备 1 个能稳定触发 3302 的样本文件；确认会被映射到 `system_pressure` 且 `lastWriteError.errorDesc` 包含可复现线索（ext/codec/路径）。

- **案例 2｜`PHPhotosErrorDomain 3305 (notEnoughSpace)` / `NSFileWriteOutOfSpaceError(640)`**
  - 现象：保存大文件（尤其视频）失败；释放空间后立即可成功。
  - 常见成因：保存过程中可能出现“临时双份占用”（例如先落盘 pending，再复制进系统相册），因此需要**峰值空间** > 文件体积。
  - 验收复现建议：将设备可用空间压到 <200MB 或制造 640/ENOSPC；确认映射到 `no_space` 且 UI 文案提示“清理空间”。

- **案例 3｜权限被用户/家长控制收回（`PHPhotosErrorDomain 3310/3311` 或 authSnapshot=denied）**
  - 现象：过去能保存，现在突然全部失败；系统设置里权限已关闭/受限。
  - 验收复现建议：在系统设置把 Photos 权限改为 Denied/Restricted；确认写入走 fail-fast（<=200ms），映射到 `no_permission`，且引导用户去设置页。

---

## C.5 重试策略（Retry Policy：自动 vs 手动）

### C.5.1 Write 重试（用户可见）
触发点：Viewer 顶部阻断条 `write_failed` 的 primary action：`retry_write / 重试保存`（Prompt Catalog 已定义）。

规则（冻结）：
- 点击 `retry_write` 时：
  - 若该 item 不处于 `write_failed`：忽略（不得改变状态）
  - 若 `pendingFileRelPath` 不存在/不可读：视为不可重试 → 直接执行 `abandon_item` 同等处理（C.7.2），并记录错误快照 `errorDomain="JustPhoto" code=1002 desc="pending_missing"`
- 重试开始后：
  - `state` 立刻置为 `writing`
  - 2.0s 内禁止再次点击（`WRITE_RETRY_COOLDOWN = 2.0s`）；UI 需显示 loading（见 C.7）
- 重试次数：不设硬上限，但必须写入 `writeAttemptCount` 并在日志中可见（用于定位“用户疯狂点重试”）

### C.5.2 Write 自动重试（仅对“瞬时错误”）
目的：减少“系统抖动导致的误报 write_failed”。

仅当失败映射结果属于以下两类，允许自动重试（否则不允许）：
- `system_pressure`
- `photo_lib_unavailable`

自动重试规则（冻结）：
- 自动重试最多 **2 次**（不含首次尝试），退避：`0.3s`、`1.0s`
- 自动重试期间，item 保持 `writing`（不进入 `write_failed`，用户不应看到 write_failed）
- 若自动重试全部失败 → 才进入 `write_failed(reason)` 并触发全局阻断

> 依据：实际 PhotoKit 写入在系统压力/相册临时不可用时可能出现偶发失败；而 invalidResource 等“确定性失败”重试无意义。

### C.5.3 Album Add 重试（沿用 6.1.4，补 UI 合约）
- 用户点击 `retry_album_add / 修复`（Prompt Catalog）：
  - 对“本 session 中所有 `album_add_failed` 项”批量重试一次（6.1.4）
  - 每个 item 的 `albumAttemptCount += 1`，并写入 `lastAlbumError`（若失败）
- 自动重试：沿用 6.1.4 的 3 次（1s/3s/10s）

---

## C.6 Thumb 流水线：生成、超时、永久失败与自愈

### C.6.1 真实缩略图生成的来源优先级（冻结）
对每个 item，真实缩略图来源按以下优先级选择（命中即用，不再向下）：

1) **本地 pending file**（优先）：从 `pendingFileRelPath` 生成缩略图  
   - 优点：不依赖相册读取权限；生成更快；更可控
2) **系统相册 asset**（降级）：当且仅当 `assetId` 可用且本地源不可用时，从系统相册按 `assetId` 请求缩略图（可能受权限/系统调度影响）
3) **占位**：若以上都不可用，继续显示 optimistic thumb，并进入 thumb_failed 流程（不影响原图）

### C.6.2 计时与状态（冻结）
- 从 `optimisticThumbShownAtMs` 开始计时：
  - **5.0s**：若仍未替换为真实缩略图 → 标记 `thumb_failed`（并在用户进入该项 Viewer 时 emit `thumb_failed`）
  - **30.0s**：若仍未替换 → 视为“永久失败”，Viewer 顶部提示必须额外出现按钮：`重建缩略`（见 C.7.4）

### C.6.3 自愈（Late Success）
- 即使已进入 `thumb_failed`，只要后续任意时刻真实缩略图生成成功：
  - 必须立刻替换 UI（filmstrip + Viewer），并把状态更新为 `thumb_ready`
  - 若 Viewer 顶部正在显示 `thumb_failed` Banner：允许自动消失（按 L2 规则）

### C.6.4 缩略缓存与尺寸（必须量化）
缩略图缓存写入规则：
- filmstrip 缩略：正方形 JPEG（或 HEIF）缓存，边长 `THUMB_FILMSTRIP_PX = 256`（含 2x/3x 统一为像素尺寸，不用点数）
- Viewer 预览缩略（用于首帧）：边长 `THUMB_VIEWER_PX = 1024`（可与 filmstrip 共用同一文件，若实现想简化）
- JPEG 质量：`0.85`（固定）
- 缓存路径：沿用附录 B 的 `thumb/` 目录策略；文件名必须包含 `SessionItem.itemId`，防冲突。

---

## C.7 UI 合约（实现者只能按这里做）

### C.7.1 filmstrip 单元格（按状态渲染）
- `captured_preview`：
  - 显示 optimistic thumb
  - 右上角显示小型 spinner（表示“正在保存”）
- `writing`：
  - 显示 optimistic thumb 或已生成真实 thumb（若已替换）
  - spinner 必须持续显示
- `write_success`：
  - 显示真实 thumb（若已 ready）或 optimistic（若仍在生成 thumb）
  - spinner 必须消失
- `write_failed`：
  - 显示 optimistic thumb（若有）否则占位灰底
  - 叠加错误角标 `!`（右上角）
  - 点击进入 Viewer（并触发 viewerBlockingBarTop：write_failed）
- `thumb_failed`：
  - 允许继续显示 optimistic（或已生成但未替换的任何 thumb）
  - 叠加小型虚线/裂纹角标（表示“缩略异常，但可看原图”）
- `album_add_failed`：
  - 不改变缩略外观（避免干扰拍摄心流）
  - 只通过相机页 Banner 提示修复（Prompt Catalog）

### C.7.2 Viewer：write_failed 阻断条（完全由 Prompt Catalog 驱动）
- 进入 `write_failed` 项的 Viewer 时，必须展示 `viewerBlockingBarTop`（key=`write_failed`），按钮行为：
  - `retry_write`：按 C.5.1
  - `abandon_item`：按 C.7.3
- 阻断条存在期间：
  - 允许查看当前图（来自 pending file 或 optimistic thumb）
  - 禁止“进入 Wrap/导出/分享”（若已有相关入口，必须 disable）

### C.7.3 abandon_item（放弃此张）的确定性效果
- 从 session 工作集中移除该 item（workset_count 立刻减 1）
- 删除与该 item 相关的本地文件（若存在）：
  - pending file
  - thumb cache（optimistic/真实）
- 关闭 Viewer 并回到相机页（或回到 filmstrip 列表视图）
- 若这是最后一个 `write_failed`：
  - 相机页快门应立即恢复（仍需受 in-flight 与 20 张上限影响）

### C.7.4 Viewer：thumb_failed 的“重建缩略”
当满足“永久失败”（30.0s）且用户正在 Viewer 查看该 item：
- 在 Viewer 顶部（`thumb_failed` Banner 下方或右侧）额外出现按钮：`重建缩略`
- 点击后执行：
  - `thumbAttemptCount += 1`
  - 重新走 C.6.1 的缩略生成流程（优先本地源，其次 asset）
  - 期间按钮变为 loading，且 2.0s 内不可重复点击（cooldown=2.0s）

> 注：Prompt Catalog 的 `thumb_failed` 不包含按钮，因此该按钮是 Viewer 内的独立 CTA（不属于 Prompt 系统槽位）。

### C.7.5 相机页：blocked_by_write_failed（解释入口）
当快门因存在 write_failed 而 disabled 时：
- 必须展示 L2 Banner（key=`blocked_by_write_failed`）
- 点击 primary：`open_first_write_failed` → 打开“最早/最前”的 write_failed 项（以 filmstrip 顺序：最新在前，则取第一个 write_failed）

---

## C.8 持久化与崩溃/后台边缘情况（必须覆盖）

### C.8.1 pending file 的保留与清理（防“我还能不能找回”）
- `write_success` 后 pending file **不得立即删除**。满足以下任一条件才允许删除：
  1) 真实缩略图已生成并落盘（thumb_ready）
  2) Viewer 已成功加载出首帧原图（不再依赖 pending file）
  3) item 已被用户从 workset 移除（清理未喜欢/重置会话/放弃此张）

- 过期清理（防占空间）：
  - 若 item 已 `write_success` 且 pending file 仍存在：
    - `PENDING_TTL_SUCCESS = 24h` 后可删除
  - 若 item 为 `write_failed`：
    - `PENDING_TTL_FAILED = 24h` 后可删除，但删除前必须：
      - 若该 item 仍在 workset 中：强制将其标记为“不可重试”（下一次进入 Viewer 时提示 `write_failed` 仍在，但 retry 会走 C.5.1 的 pending_missing 分支并引导用户放弃）

### C.8.2 App 进入后台/被系统挂起
- 当存在任意 item 处于 `writing`，App 即将进入后台时：
  - 必须向系统申请有限后台时间以完成写入（避免因中断导致 write_failed 假阴性）
- 若系统仍终止 App：
  - 下次启动进入相机页时执行恢复（见 C.8.3）

### C.8.3 冷启动恢复（Recover）
启动时若发现会话里存在以下状态，必须执行对应恢复动作：

- `captured_preview` 且超过 `CAPTURE_DATA_DEADLINE(2.0s)` 仍无 pending file：
  - 视为 `capture_failed` 的“残留条目”，必须从 workset 移除（不让空卡片污染）
- `writing`：
  - 若 pending file 仍存在：将其转为 `write_failed(photo_lib_unavailable)` 并全局阻断（因为写入结果未知，但必须可解释、可处理）
  - 若 pending file 不存在：直接移除该 item（视为不可恢复）
- `write_failed`：
  - 保持不变；相机页照样阻断快门（C.2.2）
- `thumb_failed`：
  - 启动一次后台自愈：重新尝试生成真实缩略（不弹提示；成功则更新为 thumb_ready）

---

## C.9 QA 可直接照抄的关键用例（验收清单）
> 每条都必须“可复现、可判定通过/失败”。

1) **Optimistic thumb 时序**：连拍 5 次，filmstrip 每次在 120ms 内出现新卡片（不要求真实缩略）。
2) **in-flight=2 阻断**：快速连拍触发 2 个 in-flight，第 3 次快门必 disabled，且 Banner“保存中…”出现；in-flight<2 后自动恢复。
3) **写入失败阻断**：模拟权限 denied 或相册不可用，出现 `write_failed` 后快门必禁用；相机页必出现 `blocked_by_write_failed`。
4) **手动重试成功**：write_failed → Viewer 点重试 → 状态变 writing → 成功后变 write_success 且快门恢复。
5) **放弃此张**：write_failed → 放弃此张 → 条目消失、相关缓存删除、快门恢复。
6) **thumb_failed 5s**：人为延迟 thumb 生成 >5s，进入 Viewer 必出现 `thumb_failed` Banner；随后生成成功必须自愈并替换。
7) **thumb 永久失败 30s**：延迟 >30s，Viewer 必出现“重建缩略”按钮；点后开始重建且 2s 冷却。
8) **album_add_failed 修复**：断开相册写入归档路径使 album add 失败→相机页 Banner 出现→点修复后批量重试→成功后 Banner 消失。
9) **冷启动恢复**：kill app 于 writing；重启后该条目必须变 write_failed(photo_lib_unavailable) 并阻断快门，可重试/放弃。

---




## C.10 硬验收断言（逐条可测；实现者不得“解释性实现”）

> 本节把附录 C 的每条规则进一步“压缩”为**硬断言**（可判定通过/失败）。  
> 约定：若未特别说明，时间以用户触发动作时刻为 `T0`，并以 `nowMs`（单调时钟）计算。

### C.10.0 统一判定口径（避免“各测各的”）
1) **状态=事实**：验收以 `SessionStore.workset[].state` 为准；UI 只是该状态的投影，不允许“UI 看起来对但状态不对”。  
2) **一次拍照=一次 itemId**：用户每按一次快门，最多只会新增 1 个 `SessionItem(itemId)`；不得出现“同一快门生成 2 个 item”。  
3) **同一 item 的状态单调**：除 `thumb_failed → thumb_ready`、`album_add_failed → album_add_success`、`write_failed → writing → write_success`（重试）外，其他方向的回退/跳转一律判失败。  
4) **失败必须可解释**：任何进入 `*_failed` 的路径都必须写入 `last*Error`（`SaveErrorSnapshot`），且 `errorDomain` 不能为空（没有则填 `"(none)"`）。  

### C.10.1 全局门控（Gates）断言
- **ASSERT-C-GATE-001｜in-flight 计数口径唯一**
  - Given：workset 中存在任意 `captured_preview` 或 `writing`
  - Then：`in_flight_count == count(state ∈ {captured_preview, writing})`（必须精确相等；不允许把 `thumb_failed` 等算进去）

- **ASSERT-C-GATE-002｜in-flight>=2 必阻断快门**
  - Given：`in_flight_count == 2`
  - When：用户再次点击快门（任何输入方式：触屏/外接按钮）
  - Then：快门立即 disabled（同帧或下一帧，<=16ms）
  - And：展示 L2 Banner“保存中…”（无按钮）
  - And：当 `in_flight_count < 2` 后 Banner 必自动消失且快门自动恢复（不需要用户操作）

- **ASSERT-C-GATE-003｜存在 write_failed 必阻断快门（最高优先级）**
  - Given：workset 中存在任意 `write_failed(*)`
  - Then：快门必须 disabled（即使 workset_count < 20）
  - And：相机页必须 emit 埋点/日志 `blocked_by_write_failed`（一次进入阻断态只发 1 次；离开阻断态后再次进入才可再发）
  - And：阻断态只允许通过两条路径解除：
    1) 对该失败项 `retry_write` 直到 `write_success`；
    2) 对该失败项执行 `abandon_item` 并从 workset 移除。

- **ASSERT-C-GATE-004｜多失败项时的 UI 聚焦规则**
  - Given：存在 >=2 个 `write_failed`
  - Then：Viewer 顶部阻断条必须聚焦“最新的一项”（filmstrip 最新在前 → 取第一个 `write_failed`）
  - And：相机页仍保持全局阻断（直到所有 write_failed 都被处理完）

### C.10.2 Optimistic thumb（出现/替换/超时）断言
- **ASSERT-C-TH-001｜Optimistic thumb 出现时限**
  - When：用户点击快门（且未被 Gate 阻断）
  - Then：`T0 + 120ms` 内 filmstrip 必新增 1 个条目，且其 `state == captured_preview`
  - And：UI 必展示 optimistic thumb（允许占位图，但不得空白）

- **ASSERT-C-TH-002｜Optimistic thumb 记录口径**
  - When：该条目第一次被真实渲染到 UI（而非仅数据插入）
  - Then：必须写入 `optimisticThumbShownAtMs`（且仅写一次，后续不得被覆盖）

- **ASSERT-C-TH-003｜Optimistic→真实缩略必须“原地替换”**
  - Given：同一 `SessionItem.itemId`
  - When：真实缩略生成完成
  - Then：UI 必在同一条目位置替换缩略（`itemId` 不变；不得 delete+insert 造成列表跳动）
  - And：`state` 必最终到达 `thumb_ready`（即使该项同时处于 write_failed，也必须能显示真实缩略：来源优先 pending file）

- **ASSERT-C-TH-004｜5.0s 超时标记**
  - Given：`optimisticThumbShownAtMs` 已存在
  - When：`optimisticThumbShownAtMs + 5.0s` 仍未完成真实缩略落盘
  - Then：该 item 必进入 `thumb_failed`（不影响快门）
  - And：进入 Viewer 时必须出现对应 Banner（按 Prompt Catalog）

- **ASSERT-C-TH-005｜30.0s 永久失败升级**
  - When：`optimisticThumbShownAtMs + 30.0s` 仍未完成真实缩略落盘
  - Then：Viewer 必显示“重建缩略”按钮
  - And：按钮点击触发 `rebuild_thumb`，并强制 `THUMB_REBUILD_COOLDOWN=2.0s`（2s 内重复点击必须无效且不触发重复任务）

- **ASSERT-C-TH-006｜thumb_failed 自愈**
  - Given：item 已处于 `thumb_failed`
  - When：后台自愈/重建最终生成真实缩略
  - Then：必须自动切回 `thumb_ready` 并替换 UI（不弹 toast，不需要用户确认）

### C.10.3 Write（写入系统相册）断言
- **ASSERT-C-WR-001｜pending file 必须先落地（防“拍到了但丢了”）**
  - When：捕获回调返回原始媒体数据
  - Then：必须先把数据原子写入 `Application Support/.../pending/<itemId>.<ext>`（写 tmp→rename）
  - And：写入成功后才允许触发 PhotoKit 写入请求
  - And：pending file 必满足：`exists && readable && sizeBytes > 0`

- **ASSERT-C-WR-002｜2.0s 数据期限（CAPTURE_DATA_DEADLINE）**
  - Given：item 已进入 `captured_preview`
  - When：`T0 + 2.0s` 仍未生成可读的 pending file
  - Then：该 item 必走 `capture_failed` 并从 workset 移除（不得残留空卡片）
  - And：不得进入 `write_failed`（因为根本没有可写数据）

- **ASSERT-C-WR-003｜写入回调超时（WRITE_CALLBACK_TIMEOUT=12.0s）**
  - Given：item 已进入 `writing`
  - When：`writingStartedAt + 12.0s` 仍未得到明确 completion（success/error）
  - Then：必须强制转为 `write_failed(photo_lib_unavailable)` 并全局阻断快门
  - And：`lastWriteError.errorDomain="JustPhoto" errorCode=1001 errorDesc` 必包含 `write_timeout`

- **ASSERT-C-WR-004｜权限 fail-fast**
  - Given：写入尝试开始时 `photoAuthSnapshot.status ∈ {denied, restricted, not_determined}`
  - Then：不得调用 PhotoKit 写入（避免系统弹窗/未定义行为）
  - And：必须在 `T0 + 200ms` 内把该 item 置为 `write_failed(no_permission)` 并阻断快门

- **ASSERT-C-WR-005｜映射函数必须确定性**
  - Given：同一组输入（`photoAuthSnapshot + freeMB + NSError(domain/code/underlying)`）
  - Then：`mapWriteFailReason(...)` 必返回同一个 `WriteFailReason`（不能用随机/时间/机型分支）

- **ASSERT-C-WR-006｜空间不足判定必须覆盖系统常见信号**
  - Given：任一条件成立：
    1) `freeMB < 200`（DISK_BLOCK_MB）
    2) `NSError.domain==NSCocoaErrorDomain && code==640`（NSFileWriteOutOfSpaceError）
    3) `NSError.domain==NSPOSIXErrorDomain && code==28`（ENOSPC）
    4) `NSError.domain==PHPhotosErrorDomain && code==3305`（NotEnoughSpace，业界常见）
  - Then：必须映射为 `no_space`（不允许落到 system_pressure）

- **ASSERT-C-WR-007｜权限不足判定必须覆盖系统常见信号**
  - Given：任一条件成立：
    1) `photoAuthSnapshot.status ∈ {denied, restricted, not_determined}`
    2) `NSError.domain==PHPhotosErrorDomain && code ∈ {3310, 3311}`（AccessRestricted/AccessUserDenied）
  - Then：必须映射为 `no_permission`

- **ASSERT-C-WR-008｜invalidResource 必进 system_pressure（但要补充可复现信息）**
  - Given：`NSError.domain==PHPhotosErrorDomain && code==3302`（invalidResource）
  - Then：必须映射为 `system_pressure`
  - And：`lastWriteError.errorDesc` 必包含至少 1 个可复现线索（例如：ext/codec/文件路径不可读等；见 C.4.3 的校验项）

- **ASSERT-C-WR-009｜自动重试仅限“瞬时错误”**
  - Given：首次写入失败映射为 `system_pressure` 或 `photo_lib_unavailable`
  - Then：允许自动重试最多 2 次（退避 0.3s / 1.0s）
  - And：自动重试期间 item 必保持 `writing`（不得出现 `write_failed` UI）
  - And：若仍失败才进入 `write_failed(reason)` 并阻断

- **ASSERT-C-WR-010｜手动重试冷却与幂等**
  - Given：item 处于 `write_failed`
  - When：用户点击 `retry_write`
  - Then：必须立刻置为 `writing` 并显示 loading
  - And：在 `2.0s` 冷却期内再次点击必须无效（不增 attemptCount，不触发新写入）

- **ASSERT-C-WR-011｜pending_missing 的确定性处理**
  - Given：用户点击 `retry_write`，但 `pendingFileRelPath` 不存在或不可读
  - Then：必须直接按 `abandon_item` 路径处理（条目移除 + 缓存清理）
  - And：必须写入 `lastWriteError.errorDomain="JustPhoto" errorCode=1002 errorDesc` 含 `pending_missing`

- **ASSERT-C-WR-012｜成功态必须具备 assetId 且可检索（含短重试）**
  - When：PhotoKit 写入成功回调返回
  - Then：item 必进入 `write_success(assetId)` 且 `assetId` 必持久化
  - And：在 `+2.0s` 内必须完成 “Post-Write Verification”：通过 `assetId` 尝试 fetch `PHAsset`
  - And：若首次 fetch 返回空，允许在 **500ms** 后重试 1 次（总时限仍 ≤ 2.0s）
  - And：在验证窗口内 **不得** 将 item 从 `write_success` 降级为 `write_failed`
  - And：若超过 2.0s 仍 fetch 为空：必须记录 `post_write_verification_delayed`（本地日志），并继续保持 `write_success(assetId)`；后续缩略/归档允许延迟重试直至可读

### C.10.4 Album Add（归档进 Just Photo 相册）断言
- **ASSERT-C-AL-001｜只在 write_success 后触发**
  - Given：item 未 `write_success`
  - Then：不得触发 album add（避免无效请求与乱序）

- **ASSERT-C-AL-002｜失败不阻断快门**
  - Given：出现任意 `album_add_failed`
  - Then：快门不得被 disabled（除非同时存在 write_failed 等其他 Gate）

- **ASSERT-C-AL-003｜自动重试节奏固定**
  - Given：某 item `album_add_failed`
  - Then：必须自动重试 3 次（退避 1s / 3s / 10s）
  - And：超过 3 次仍失败才保持 `album_add_failed` 并由用户“修复”触发批量重试

- **ASSERT-C-AL-004｜“修复”必须批量且可幂等**
  - When：用户点击 `retry_album_add / 修复`
  - Then：必须对“本 session 中所有 album_add_failed”各重试 1 次（不重复、不遗漏）
  - And：过程中允许用户继续拍照（不阻断）

### C.10.5 持久化/崩溃/后台断言（防数据灾难）
- **ASSERT-C-REC-001｜关键节点必须落盘**
  - When：发生以下任一事件：
    1) 插入 `captured_preview`
    2) 进入 `write_failed`
    3) App `willResignActive/didEnterBackground`
  - Then：`current_session` 必在 200ms 内完成一次落盘（可 debounce，但这三类事件不得延后）

- **ASSERT-C-REC-002｜杀进程于 writing 的恢复必须可解释**
  - Given：App 在某 item 为 `writing` 时被杀
  - When：冷启动恢复
  - Then：若 pending file 仍存在 → 必转 `write_failed(photo_lib_unavailable)` 并阻断快门（结果未知必须显式暴露给用户）
  - Else（pending 不存在）→ 必移除该 item（不可恢复）

- **ASSERT-C-REC-003｜pending file 删除条件严格**
  - Given：item 已 `write_success`
  - Then：pending file 不得立即删除；必须满足 C.8.1 的任一条件后才可删
  - And：若 pending file 过期被删且 item 仍为 `write_failed`，必须将其标记为“不可重试”（下一次 retry 走 pending_missing）

### C.10.6 UI 合约断言（只看 PRD 就能画界面/写代码）
- **ASSERT-C-UI-001｜write_failed 阻断条必含 2 个动作**
  - Given：Viewer 正在展示某 `write_failed`
  - Then：顶部阻断条必须提供：
    1) primary：`retry_write / 重试保存`
    2) secondary：`abandon_item / 放弃此张`
  - And：两者 actionId 必与 Prompt Catalog 一致（不得另起名字）

- **ASSERT-C-UI-002｜写入失败 reason 文案唯一**
  - Given：`write_failed(reasonEnum)`
  - Then：Prompt `{reason}` 必严格使用 C.4.1 的中文短语：`权限不足/空间不足/系统相册不可用/系统繁忙`
  - And：不得展示 enum rawValue、英文 domain 或 code

- **ASSERT-C-UI-003｜写入失败后快门禁用的“可见解释”**
  - Given：相机页被 `write_failed` 阻断
  - Then：必须有明确可见的阻断提示（Banner/条），且点击可定位到失败项（进入 Viewer 并选中该条目）

### C.10.7 可观测性断言（便于 QA 与线上定位）
- **ASSERT-C-OBS-001｜每次状态转移都要可追踪**
  - When：任一 item 状态发生变化
  - Then：必须输出一条结构化日志（或埋点）包含：
    - `sessionId, itemId, prevState, nextState, attemptCount(write/album/thumb), tsMs`
  - And：若 nextState 为任一 `*_failed`，必须附带 `SaveErrorSnapshot`（至少 domain/code/freeMB/auth）

- **ASSERT-C-OBS-002｜“用户疯狂点击”不得压垮保存队列**
  - Given：用户在 1 秒内连续点击 `retry_write` 10 次
  - Then：实际触发的写入任务数必须 ≤1（受 2.0s 冷却约束）
  - And：`writeAttemptCount` 不得因被忽略的点击而增长

---

### C.10.8 断言集与 C.9 Smoke 的关系（验收策略）
- **C.10**：作为“严格验收基线”（必须全过）。  
- **C.9**：作为“快速回归 smoke”（每次提测必跑，节省时间）。  

---


### 附录 D｜PoseSpec 最小可实现表（冻结）

> 本表为 **V1 最小可实现集合**：实现方必须支持表中每条 cue 的输入依赖、阈值、去抖、fallback 与 QA 资产回归。  
> 数据来源：PoseSpec `PoseSpec`（schemaVersion=0.1, prdVersion=v1.1.4, generatedAt=2026-01-29）。

#### D.0 口径说明（冻结）
- **误差（error）口径**：
  - 若 cue.trigger.noRef/withRef 显式提供 `error` 表达式 → 以该表达式为准。
  - 否则：以该 cue 的 `metric.outputs`（单一输出）作为 error。
- **阈值语义**（统一）：
  - `warn/hard/exit` 为进入/加重/退出阈值；满足 `exit` 连续 `persistFrames` 帧后才视为退出。
- **withRef 支持**：
  - `withRef=Y`：表示该 cue 允许参考图对齐（使用 `target.*`）。
  - `withRef=N`：withRef 模式下该 cue 仍可被选中，但必须按 noRef 规则计算（不得使用 target）。
- **去抖与展示时长**：`antiJitter.minHoldMs` 必 ≥ 3000ms（保证台词卡至少可读 3 秒，除非被更高优先级严重问题插队）。
- **QA 回归**：每条 cue 必须能用 `QA_before/QA_after` 资产复现触发与退出；资产缺失视为该 cue 不可验收。

#### D.1 Cue 列表（V1，冻结）
| cueId | scene | priority | mutexGroup | requires | tier | updateHz | outputs | noRef_error | noRef_th | withRef | withRef_error | withRef_th | minConf | fallback | antiJitter | QA_before | QA_after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FRAME_MOVE_LEFT | base | 4 | FRAME_X | pose | T0 | 15 | centerXOffset | centerXOffset | warn:>0.07 / hard:>0.12 / exit:<=0.04 | Y | centerXOffset - target.centerXOffset | warn:>0.07 / hard:>0.12 / exit:<=0.04 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/FRAME_MOVE_LEFT_before.jpg | QA/base/FRAME_MOVE_LEFT_after.jpg |
| FRAME_MOVE_RIGHT | base | 4 | FRAME_X | pose | T0 | 15 | centerXOffset | centerXOffset | warn:<-0.07 / hard:<-0.12 / exit:>=-0.04 | Y | centerXOffset - target.centerXOffset | warn:<-0.07 / hard:<-0.12 / exit:>=-0.04 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/FRAME_MOVE_RIGHT_before.jpg | QA/base/FRAME_MOVE_RIGHT_after.jpg |
| FRAME_MOVE_UP | base | 4 | FRAME_Y | pose | T0 | 15 | centerYOffset | centerYOffset | warn:>0.08 / hard:>0.14 / exit:<=0.06 | Y | centerYOffset - target.centerYOffset | warn:>0.08 / hard:>0.14 / exit:<=0.06 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/FRAME_MOVE_UP_before.jpg | QA/base/FRAME_MOVE_UP_after.jpg |
| FRAME_MOVE_DOWN | base | 4 | FRAME_Y | pose | T0 | 15 | centerYOffset | centerYOffset | warn:<-0.08 / hard:<-0.14 / exit:>=-0.06 | Y | centerYOffset - target.centerYOffset | warn:<-0.08 / hard:<-0.14 / exit:>=-0.06 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/FRAME_MOVE_DOWN_before.jpg | QA/base/FRAME_MOVE_DOWN_after.jpg |
| DIST_STEP_CLOSER | base | 4 | DIST | pose | T0 | 15 | bboxHeight | bboxHeight | warn:<0.49 / hard:<0.43 / exit:>=0.55 | Y | bboxHeight - target.bboxHeight | warn:<-0.06 / hard:<-0.12 / exit:>=0.0 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/DIST_STEP_CLOSER_before.jpg | QA/base/DIST_STEP_CLOSER_after.jpg |
| DIST_STEP_BACK | base | 4 | DIST | pose | T0 | 15 | bboxHeight | bboxHeight | warn:>0.83 / hard:>0.88 / exit:<=0.78 | Y | bboxHeight - target.bboxHeight | warn:>0.05 / hard:>0.1 / exit:<=0.0 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/DIST_STEP_BACK_before.jpg | QA/base/DIST_STEP_BACK_after.jpg |
| FRAME_ADD_HEADROOM | base | 4 | FRAME_HEADROOM | pose | T0 | 15 | headroom | headroom | warn:<0.05 / hard:<0.02 / exit:>=0.09 | Y | headroom - target.headroom | warn:<-0.02 / hard:<-0.05 / exit:>=0.09 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/FRAME_ADD_HEADROOM_before.jpg | QA/base/FRAME_ADD_HEADROOM_after.jpg |
| FRAME_DONT_CROP_FEET | base | 4 | FRAME_FOOT | pose | T0 | 15 | bottomMargin | bottomMargin | warn:<0.03 / hard:<0.0 / exit:>=0.05 | Y | bottomMargin - target.bottomMargin | warn:<-0.02 / hard:<-0.05 / exit:>=0.05 | 0.5 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/FRAME_DONT_CROP_FEET_before.jpg | QA/base/FRAME_DONT_CROP_FEET_after.jpg |
| SHOULDER_LEVEL_LEFT_DOWN | base | 3 | SHOULDER_LEVEL | pose | T0 | 15 | shoulderAngleDeg | shoulderAngleDeg | warn:>8 / hard:>14 / exit:<=5 | Y | shoulderAngleDeg - target.shoulderAngleDeg | warn:>8 / hard:>14 / exit:<=5 | 0.6 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/SHOULDER_LEVEL_LEFT_DOWN_before.jpg | QA/base/SHOULDER_LEVEL_LEFT_DOWN_after.jpg |
| SHOULDER_LEVEL_RIGHT_DOWN | base | 3 | SHOULDER_LEVEL | pose | T0 | 15 | shoulderAngleDeg | shoulderAngleDeg | warn:<-8 / hard:<-14 / exit:>=-5 | Y | shoulderAngleDeg - target.shoulderAngleDeg | warn:<-8 / hard:<-14 / exit:>=-5 | 0.6 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/SHOULDER_LEVEL_RIGHT_DOWN_before.jpg | QA/base/SHOULDER_LEVEL_RIGHT_DOWN_after.jpg |
| HIP_SQUARE | base | 3 | HIP_LEVEL | pose | T0 | 15 | hipAngleDeg | hipAngleDeg | warn:abs>10 / hard:abs>16 / exit:abs<=6 | Y | hipAngleDeg - target.hipAngleDeg | warn:abs>10 / hard:abs>16 / exit:abs<=6 | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/HIP_SQUARE_before.jpg | QA/base/HIP_SQUARE_after.jpg |
| TORSO_STRAIGHTEN | base | 3 | TORSO | pose | T0 | 15 | torsoLeanAngleDeg | torsoLeanAngleDeg | warn:abs>10 / hard:abs>16 / exit:abs<=6 | Y | torsoLeanAngleDeg - target.torsoLeanAngleDeg | warn:abs>10 / hard:abs>16 / exit:abs<=6 | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/TORSO_STRAIGHTEN_before.jpg | QA/base/TORSO_STRAIGHTEN_after.jpg |
| HEAD_LEVEL | base | 3 | HEAD_TILT | face | T0 | 15 | eyeLineAngleDeg | eyeLineAngleDeg | warn:abs>7 / hard:abs>12 / exit:abs<=4 | Y | eyeLineAngleDeg - target.eyeLineAngleDeg | warn:abs>7 / hard:abs>12 / exit:abs<=4 | 0.6 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/HEAD_LEVEL_before.jpg | QA/base/HEAD_LEVEL_after.jpg |
| CHIN_DOWN | base | 3 | CHIN | face | T0 | 15 | noseToChinRatio | noseToChinRatio | warn:<0.34 / hard:<0.32 / exit:between[0.36, 0.42] | Y | noseToChinRatio - target.noseToChinRatio | warn:<-0.02 / hard:<-0.04 / exit:between[0.36, 0.42] | 0.65 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/CHIN_DOWN_before.jpg | QA/base/CHIN_DOWN_after.jpg |
| CHIN_UP | base | 3 | CHIN | face | T0 | 15 | noseToChinRatio | noseToChinRatio | warn:>0.44 / hard:>0.46 / exit:between[0.36, 0.42] | Y | noseToChinRatio - target.noseToChinRatio | warn:>0.02 / hard:>0.04 / exit:between[0.36, 0.42] | 0.65 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/CHIN_UP_before.jpg | QA/base/CHIN_UP_after.jpg |
| HAND_OFF_FACE | base | 3 | HANDS | pose,face | T0 | 15 |  | implicit | warn:<0.24 / hard:<0.18 / exit:>=0.3 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/base/HAND_OFF_FACE_before.jpg | QA/base/HAND_OFF_FACE_after.jpg |
| ARMS_RELAX | base | 3 | ARMS | pose | T0 | 15 |  | implicit | warn:<50 / hard:<40 / exit:>=60 | N |  | warn: / hard: / exit: | 0.5 | FRAME_GENERAL | pf=7,holdMs=3000,cdMs=0 | QA/base/ARMS_RELAX_before.jpg | QA/base/ARMS_RELAX_after.jpg |
| SHOULDERS_OPEN | base | 3 | POSTURE | pose | T0 | 15 |  | implicit | warn:<0.9 / hard:<0.85 / exit:>=0.95 | N |  | warn: / hard: / exit: | 0.5 | FRAME_GENERAL | pf=7,holdMs=3000,cdMs=0 | QA/base/SHOULDERS_OPEN_before.jpg | QA/base/SHOULDERS_OPEN_after.jpg |
| WEIGHT_SHIFT | base | 3 | STANCE | pose | T0 | 15 |  | implicit | warn:abs<0.01 / hard: / exit:abs>=0.02 | N |  | warn: / hard: / exit: | 0.5 | FRAME_GENERAL | pf=8,holdMs=3000,cdMs=0 | QA/base/WEIGHT_SHIFT_before.jpg | QA/base/WEIGHT_SHIFT_after.jpg |
| FRAME_GENERAL | base | 6 | FALLBACK |  | fallback | 15 |  | N/A | warn: / hard: / exit: | N |  | warn: / hard: / exit: | 0.5 | FRAME_GENERAL | pf=3,holdMs=3000,cdMs=0 | QA/base/FRAME_GENERAL_before.jpg | QA/base/FRAME_GENERAL_after.jpg |
| CAFE_01_FACE_TOO_DARK | cafe | 5 | LIGHT_FACE | face,frame | T1 | 2 | faceLumaMean | faceLumaMean | warn:>0.08 / hard:>0.14 / exit:<=0.0 | Y | faceLumaMean - target.faceLumaMean | warn:<-0.08 / hard:<-0.14 / exit:>=0.0 | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_01_FACE_TOO_DARK_before.jpg | QA/cafe/CAFE_01_FACE_TOO_DARK_after.jpg |
| CAFE_02_FACE_BACKLIT | cafe | 5 | LIGHT_BG | face,frame | T1 | 2 |  | error (from formula) | warn:>0.2 / hard:>0.35 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_02_FACE_BACKLIT_before.jpg | QA/cafe/CAFE_02_FACE_BACKLIT_after.jpg |
| CAFE_03_FACE_OVEREXPOSED | cafe | 5 | LIGHT_FACE | face,frame | T1 | 2 |  | error (from formula) | warn:>0.04 / hard:>0.1 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_03_FACE_OVEREXPOSED_before.jpg | QA/cafe/CAFE_03_FACE_OVEREXPOSED_after.jpg |
| CAFE_04_FACE_TOO_FLAT | cafe | 4 | LIGHT_FACE | face,frame | T1 | 2 |  | error (from formula) | warn:>0.03 / hard:>0.06 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_04_FACE_TOO_FLAT_before.jpg | QA/cafe/CAFE_04_FACE_TOO_FLAT_after.jpg |
| CAFE_05_WB_TOO_YELLOW | cafe | 4 | WB | frame,face | T1 | 1 |  | error (from formula) | warn:>500 / hard:>900 / exit:<=0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_05_WB_TOO_YELLOW_before.jpg | QA/cafe/CAFE_05_WB_TOO_YELLOW_after.jpg |
| CAFE_06_WB_MIXED_LIGHT | cafe | 4 | WB | frame,face | T1 | 1 |  | error (from formula) | warn:>700 / hard:>1200 / exit:<=700 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_06_WB_MIXED_LIGHT_before.jpg | QA/cafe/CAFE_06_WB_MIXED_LIGHT_after.jpg |
| CAFE_07_BG_TOO_BUSY | cafe | 4 | BG_CLUTTER | face,frame | T1 | 2 |  | error (from formula) | warn:>0.1 / hard:>0.18 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_07_BG_TOO_BUSY_before.jpg | QA/cafe/CAFE_07_BG_TOO_BUSY_after.jpg |
| CAFE_08_BG_BRIGHT_SPOT | cafe | 4 | BG_CLUTTER | face,frame | T1 | 2 |  | error (from formula) | warn:>0.03 / hard:>0.07 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_08_BG_BRIGHT_SPOT_before.jpg | QA/cafe/CAFE_08_BG_BRIGHT_SPOT_after.jpg |
| CAFE_09_GLASSES_GLARE | cafe | 4 | GLASSES | face,frame | T1 | 2 |  | error (from formula) | warn:>0.04 / hard:>0.1 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_09_GLASSES_GLARE_before.jpg | QA/cafe/CAFE_09_GLASSES_GLARE_after.jpg |
| CAFE_10_LOW_LIGHT_STEADY | cafe | 5 | MOTION | motion | T1 | 30 |  | error (from formula) | warn:>0.4 / hard:>0.9 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=4,holdMs=3000,cdMs=0 | QA/cafe/CAFE_10_LOW_LIGHT_STEADY_before.jpg | QA/cafe/CAFE_10_LOW_LIGHT_STEADY_after.jpg |
| CAFE_11_EYES_TOWARD_LIGHT | cafe | 2 | LIGHT_FACE | face,frame | T1 | 2 |  | error (from formula) | warn:>0.04 / hard:>0.08 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_11_EYES_TOWARD_LIGHT_before.jpg | QA/cafe/CAFE_11_EYES_TOWARD_LIGHT_after.jpg |
| CAFE_12_CAFE_THIRDS_COMPOSE | cafe | 4 | COMPOSE_CAFE | pose | T0 | 15 |  | implicit | warn:>0.1 / hard:>0.16 / exit:<=0.06 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_12_CAFE_THIRDS_COMPOSE_before.jpg | QA/cafe/CAFE_12_CAFE_THIRDS_COMPOSE_after.jpg |
| CAFE_13_KEEP_FACE_CLEAR_OF_MENU | cafe | 4 | HANDS | pose,face | T0 | 15 |  | error (from formula) | warn:>0.03 / hard:>0.06 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_13_KEEP_FACE_CLEAR_OF_MENU_before.jpg | QA/cafe/CAFE_13_KEEP_FACE_CLEAR_OF_MENU_after.jpg |
| CAFE_14_SHRUG_DETECTED | cafe | 3 | POSTURE | pose | T0 | 15 |  | error (from formula) | warn:>0.06 / hard:>0.1 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_14_SHRUG_DETECTED_before.jpg | QA/cafe/CAFE_14_SHRUG_DETECTED_after.jpg |
| CAFE_15_SEATED_POSTURE_STRAIGHT | cafe | 3 | POSTURE | pose | T0 | 15 |  | error (from formula) | warn:>6 / hard:>12 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/cafe/CAFE_15_SEATED_POSTURE_STRAIGHT_before.jpg | QA/cafe/CAFE_15_SEATED_POSTURE_STRAIGHT_after.jpg |
| OUT_01_FACE_IN_SHADOW | outdoor | 5 | SUN_LIGHT | face,frame | T1 | 2 |  | error (from formula) | warn:>0.1 / hard:>0.18 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_01_FACE_IN_SHADOW_before.jpg | QA/outdoor/OUT_01_FACE_IN_SHADOW_after.jpg |
| OUT_02_BACKLIGHT_SILHOUETTE | outdoor | 5 | SUN_LIGHT | face,frame | T1 | 2 |  | error (from formula) | warn:>0.18 / hard:>0.32 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_02_BACKLIGHT_SILHOUETTE_before.jpg | QA/outdoor/OUT_02_BACKLIGHT_SILHOUETTE_after.jpg |
| OUT_03_SUN_SQUINT | outdoor | 4 | SUN_LIGHT | face | T0 | 15 |  | error (from formula) | warn:>0.04 / hard:>0.08 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_03_SUN_SQUINT_before.jpg | QA/outdoor/OUT_03_SUN_SQUINT_after.jpg |
| OUT_04_SKY_BLOWOUT | outdoor | 4 | SKY | face,frame | T1 | 2 |  | error (from formula) | warn:>0.06 / hard:>0.14 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_04_SKY_BLOWOUT_before.jpg | QA/outdoor/OUT_04_SKY_BLOWOUT_after.jpg |
| OUT_05_HORIZON_LEVEL | outdoor | 4 | HORIZON | frame | T1 | 5 |  | error (from formula) | warn:abs>2.5 / hard:abs>5.0 / exit:abs<=2.5 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_05_HORIZON_LEVEL_before.jpg | QA/outdoor/OUT_05_HORIZON_LEVEL_after.jpg |
| OUT_06_VERTICALS_STRAIGHT | outdoor | 4 | BUILDING_VERTICAL | frame | T1 | 5 |  | error (from formula) | warn:abs>3.0 / hard:abs>6.0 / exit:abs<=3.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_06_VERTICALS_STRAIGHT_before.jpg | QA/outdoor/OUT_06_VERTICALS_STRAIGHT_after.jpg |
| OUT_07_LANDMARK_ALIGN_X | outdoor | 4 | LANDMARK_ALIGN | ref | T1 | 3 |  | N/A | warn: / hard: / exit: | Y | error (from formula) | warn:abs>0.05 / hard:abs>0.1 / exit:abs<=0.05 | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_07_LANDMARK_ALIGN_X_before.jpg | QA/outdoor/OUT_07_LANDMARK_ALIGN_X_after.jpg |
| OUT_08_LANDMARK_ALIGN_Y | outdoor | 4 | LANDMARK_ALIGN | ref | T1 | 3 |  | N/A | warn: / hard: / exit: | Y | error (from formula) | warn:abs>0.05 / hard:abs>0.1 / exit:abs<=0.05 | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_08_LANDMARK_ALIGN_Y_before.jpg | QA/outdoor/OUT_08_LANDMARK_ALIGN_Y_after.jpg |
| OUT_09_LANDMARK_ALIGN_ROTATE | outdoor | 4 | LANDMARK_ALIGN | ref | T1 | 3 |  | N/A | warn: / hard: / exit: | Y | error (from formula) | warn:abs>2.0 / hard:abs>4.0 / exit:abs<=2.0 | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_09_LANDMARK_ALIGN_ROTATE_before.jpg | QA/outdoor/OUT_09_LANDMARK_ALIGN_ROTATE_after.jpg |
| OUT_10_LANDMARK_SCALE_MATCH | outdoor | 4 | LANDMARK_ALIGN | ref | T1 | 3 |  | N/A | warn: / hard: / exit: | Y | error (from formula) | warn:abs>0.08 / hard:abs>0.16 / exit:abs<=0.08 | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_10_LANDMARK_SCALE_MATCH_before.jpg | QA/outdoor/OUT_10_LANDMARK_SCALE_MATCH_after.jpg |
| OUT_11_CROWD_TOO_MUCH | outdoor | 4 | CROWD | frame | T1 | 2 |  | error (from formula) | warn:>=1 / hard:>=3 / exit:<=0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_11_CROWD_TOO_MUCH_before.jpg | QA/outdoor/OUT_11_CROWD_TOO_MUCH_after.jpg |
| OUT_12_STRONG_SHADOW_STRIPES | outdoor | 4 | SUN_LIGHT | face,frame | T1 | 2 |  | error (from formula) | warn:>0.08 / hard:>0.16 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_12_STRONG_SHADOW_STRIPES_before.jpg | QA/outdoor/OUT_12_STRONG_SHADOW_STRIPES_after.jpg |
| OUT_13_LENS_FLARE_RISK | outdoor | 4 | SKY | frame | T1 | 2 |  | error (from formula) | warn:>0.08 / hard:>0.16 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_13_LENS_FLARE_RISK_before.jpg | QA/outdoor/OUT_13_LENS_FLARE_RISK_after.jpg |
| OUT_14_OUTDOOR_COMPOSE_MORE_LANDMARK | outdoor | 4 | COMPOSE_LANDMARK | pose | T0 | 15 |  | error (from formula) | warn:>0.1 / hard:>0.18 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.55 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_14_OUTDOOR_COMPOSE_MORE_LANDMARK_before.jpg | QA/outdoor/OUT_14_OUTDOOR_COMPOSE_MORE_LANDMARK_after.jpg |
| OUT_15_HAIR_COVERS_FACE | outdoor | 3 | WIND | face | T0 | 15 |  | error (from formula) | warn:>0.0 / hard:>0.1 / exit:<=0.0 | N |  | warn: / hard: / exit: | 0.45 | FRAME_GENERAL | pf=6,holdMs=3000,cdMs=0 | QA/outdoor/OUT_15_HAIR_COVERS_FACE_before.jpg | QA/outdoor/OUT_15_HAIR_COVERS_FACE_after.jpg |
