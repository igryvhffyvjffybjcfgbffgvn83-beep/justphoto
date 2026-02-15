# Codex Runbook（Just Photo）

## 常用命令

### 1) 列出 schemes
```bash
xcodebuild -list -project /Users/fanqie/Projects/opencode_just_photo/justphoto_opencode.xcodeproj
```

### 2) 跑测试（模板）
```bash
xcodebuild test -project /Users/fanqie/Projects/opencode_just_photo/justphoto_opencode.xcodeproj \
  -scheme <SCHEME_NAME> \
  -destination "platform=iOS Simulator,name=<SIM_NAME>"
```

### 3) 在 Xcode 里跑测试
- `Product > Test`（Cmd+U）

## 已解析到的测试 scheme
从共享 scheme 文件可知测试 scheme 名称为：`justphoto_opencodeTests`。
如果 `xcodebuild -list` 中也存在该 scheme，可直接用：

```bash
xcodebuild test -project /Users/fanqie/Projects/opencode_just_photo/justphoto_opencode.xcodeproj \
  -scheme justphoto_opencodeTests \
  -destination "platform=iOS Simulator,name=<SIM_NAME>"
```

若不确定设备名，先运行：
```bash
xcrun simctl list devices available
```

## 快速识别 scheme/test target
1. 运行 `xcodebuild -list -project ...` 查看 Schemes。
2. 选择包含 App 的 scheme（通常与工程同名）并确保 test target 可跑。
3. 以 `-project` 形式执行 `xcodebuild test`。

## DerivedData 定位
- 默认路径：`~/Library/Developer/Xcode/DerivedData`
- 若需要定位具体工程产物，可按时间排序或使用工程名前缀筛选。

## 常见失败排查
- **找不到 scheme**：确认已运行 `xcodebuild -list`，且 scheme 是否共享。
- **找不到设备**：先运行 `xcrun simctl list devices available`，选择可用模拟器名称。
- **构建失败**：检查最近改动文件与 build log，优先核对依赖与编译错误。
