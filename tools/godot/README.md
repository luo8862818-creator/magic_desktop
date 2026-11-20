# 本地 Godot 引擎目录

将从 Godot 官网下载的 Windows Standard 版压缩包解压到此目录。

保留 GUI 版本的可执行文件，文件名通常类似：

`Godot_v4.5-stable_win64.exe`

不要只放 `*_console.exe`。如果目录里只有一个 GUI 版 `Godot*.exe`，Magic Desktop 会自动识别它；如果有多个版本，请在控制中心手动选择。

Godot 官网：https://godotengine.org/download/windows/

注意：exe 是本地开发依赖，已通过根目录 .gitignore 排除，不会上传到 GitHub。当前阶段使用编辑器发行版 exe 启动项目；后续正式发布会改用 Godot 导出的独立运行程序。
