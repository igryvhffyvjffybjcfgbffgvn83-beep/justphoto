---
name: xctest-writer
description: 为刚创建/修改的 Swift 文件生成 XCTest 单测
---

# XCTest 编写规范

## 强制要求
- **覆盖率**：覆盖正常路径 (Happy Path) 和边缘情况 (Edge Cases)
- **独立性**：测试用例应独立运行，不依赖外部复杂状态
- **位置**：将测试代码写入项目的 `Tests` 目录下
- **完成后说明**：如何在终端或 Xcode 中运行这些测试

## 额外工程约束（必须遵守）
1. **自动识别 scheme/test target**
   - 先运行：
     `xcodebuild -list -project /Users/fanqie/Projects/opencode_just_photo/justphoto_opencode.xcodeproj`
   - 选择包含 App 的 scheme（通常同名），并确保 test target 可跑
2. **默认使用 iOS Simulator destination**
   - 若不确定设备名，先运行：
     `xcrun simctl list devices available`
3. **CLI 跑测命令必须以 -project 形式给出**
   - 这里仅有 `.xcodeproj` 路径

## 输出要求
- **Test Plan**：覆盖点列表（Happy Path / Edge Cases）
- **Test Code**：具体 XCTest 实现（位于 `Tests` 目录）
- **Run Instructions**：终端命令 + Xcode 操作步骤
- **Assumptions**：缺信息时的最安全默认假设

## 约束
- 不修改生产代码，仅新增/调整测试代码。
