# 耳机 Log 时间记录工具

一个用于耳机测试和重复操作测试的 Windows 桌面工具。预先排列测试步骤，每按一次空格就记录下一步的当前时间，减少移动鼠标再点击带来的操作延迟。

使用 Windows PowerShell 5.1、WinForms 和少量 C# 辅助代码实现，无需安装 Python、Node.js 或开发环境。

## 下载与启动

1. 点击本仓库页面的 **Code → Download ZIP**。
2. 将压缩包完整解压到固定文件夹，不要只取出一个脚本，也不要在压缩包内直接运行。
3. 双击 `StartRecorder.vbs` 启动工具。也可双击 `CreateDesktopShortcut.vbs` 创建桌面快捷方式。
4. 打开或新建记录文件，添加操作按钮，将按钮拖入右侧测试区，按上下顺序排列。
5. 按 Esc 或点击空白处退出名称输入框，再按空格开始逐步记录。

运行环境：Windows 桌面系统、Windows PowerShell 5.1 和 .NET Framework；目前在 Windows 11 上验证。此工具不支持 macOS、Linux 或浏览器直接运行。首次运行无需管理员权限；受组织策略管理的设备需按本机策略运行。

## 主要功能

- 自定义按钮，支持 Enter 连续添加、重命名、删除和拖动排序。
- 拖入测试步骤，支持重复步骤、调整顺序和连续多轮测试。
- 独立的“重做本轮”“开始下一轮”“全部重来”控制。
- 多测试方案，按钮及步骤变更自动保存。
- 时间戳、可选毫秒精度和相邻操作间隔，记录直接写入 UTF-8 文本文件。
- F8 标记异常，Ctrl+Z 撤销最近一次空格记录，支持记录编辑和删除。
- 经典布局与精简工作台可选，记住窗口位置、大小和区域比例。
- 清空记录前将完整副本送入 Windows 回收站，核实成功后再清空原文件。

## 常用操作

| 操作 | 效果 |
| --- | --- |
| 空格 | 记录下一个测试步骤；长按不会连续触发 |
| Enter | 在按钮名称框添加按钮，在记录编辑框保存修改 |
| Esc / 点击空白处 | 退出按钮名称输入，返回测试操作 |
| F8 | 写入异常标记，不推进步骤 |
| Ctrl+Z | 撤销最近一次空格记录；文字输入框仍执行文字撤销 |
| 鼠标点击操作按钮 | 记录所点按钮，不推进空格执行进度 |
| 右键测试步骤 | 从测试区移除该步骤 |

完整操作说明见 [使用说明](docs/usage.md)，也可在工具顶部点击“使用说明”。

## 配置与记录

- 记录文件由使用者自行选择位置，不随仓库分发。
- 按钮、方案及偏好保存在 `%APPDATA%\EarphoneLogTimeRecorder`。
- 启动失败时可用 `StartRecorder.bat` 查看错误，或查看 `%LOCALAPPDATA%\EarphoneLogTimeRecorder\startup-error.log`。
- 回收站中的备份可右键“还原”到原记录目录；清空回收站也会删除这些备份。

## 开发与验证

主入口为 `RecordTime.ps1`，功能按步骤管理、工作流、布局、窗口层级和回收站备份分文件组织。保留全部根目录脚本和 C# 文件；程序启动时会自动编译辅助 C# 代码。

在 Windows PowerShell 的 STA 会话中分别运行以下检查：

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Sequence.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Workflow.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Themes.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Dialogs.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-ExternalWindows.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-RecycleBackup.ps1
```

这些检查使用临时配置和记录文件。窗口测试会显示临时界面，请逐个运行，避免同时争抢焦点。回收站检查仅回收并还原测试自己的临时副本，不清空回收站。

包含中文的 `.ps1` 文件应保存为 **UTF-8 BOM**，以便 Windows PowerShell 5.1 正确读取。

## 问题反馈

可通过本仓库 Issues 提交问题。请说明 Windows 版本、界面布局、复现步骤、预期结果和实际结果；如需截图或日志，请先移除个人信息及内部测试内容。
