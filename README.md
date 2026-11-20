# Magic Desktop

Windows 桌面 3D 悬浮动画原型。当前版本完成第一阶段：Python 控制中心 + Godot 实时 3D 透明桌面窗口。

## 当前实现

- Python + PySide6 控制中心。
- Godot 4 实时 3D 场景，蛋糕由 3D Mesh 程序化生成，不是静态图片或视频。
- 无边框、透明背景、始终置顶的桌面窗口。
- 蛋糕持续旋转，蜡烛火焰动态闪烁。
- 点击蛋糕触发弹跳和粒子惊喜效果。
- 鼠标拖动窗口。
- 鼠标穿透开关：开启后鼠标操作会传递给桌面下方窗口。
- 自定义祝福文字、旋转速度。
- Godot 路径由控制中心首次运行时选择并保存。
- Python 与 Godot 通过本机 UDP（127.0.0.1）通信。

## 当前版本尚未实现

背景音乐、独立音效管理、MP4/GIF 离线导出、Blender 高精度模型和 EXE 安装包属于后续阶段。本版本不把这些未完成能力标记为已实现。

## 环境要求

- Windows 10/11（建议 64 位）。
- Python 3.11 或更高版本。
- Godot Engine 4.4 或更高版本，下载 Standard 版本（不是 .NET 版本也可以）。
- 支持桌面透明窗口的显卡驱动。透明效果可用性会受到显卡驱动和 Windows 桌面合成环境影响。

Godot 官方下载：https://godotengine.org/download/windows/

## 第一次运行

1. 下载或克隆仓库。
2. 安装 Python 3.11+ 和 Godot 4.4+。
3. 双击 `setup.bat`，创建虚拟环境并安装 PySide6。
4. 双击 `start.bat`，打开 Magic Desktop 控制中心。
5. 在控制中心点击“选择 Godot.exe”，选择 Godot 安装目录中的 Godot 可执行文件。
6. 点击“启动桌面动画”。

Godot 可执行文件通常类似：
`C:\\Godot\\Godot_v4.4-stable_win64.exe`

## 控制方式

| 操作 | 效果 |
|---|---|
| 鼠标左键拖动蛋糕区域 | 移动桌面悬浮窗口 |
| 鼠标左键点击蛋糕 | 蛋糕弹跳并触发粒子效果 |
| 控制中心修改祝福语 | 更新 3D 文字 |
| 控制中心调整旋转速度 | 实时调整旋转速度 |
| 鼠标穿透开关 | 开启后不再拦截桌面鼠标操作 |
| 隐藏 / 显示 | 隐藏或重新显示 3D 窗口 |
| 停止引擎 | 退出 Godot 进程 |

提示：开启鼠标穿透后，蛋糕无法接收点击和拖动。需要交互时，请在控制中心关闭鼠标穿透。

## 目录结构

```text
magic_desktop/
├── app/
│   ├── __init__.py
│   └── main.py
├── config/
│   └── settings.json
├── engine/
│   ├── project.godot
│   ├── scenes/
│   │   └── main.tscn
│   └── scripts/
│       └── main.gd
├── logs/                 # 运行时生成，不上传
├── output/               # 后续导出目录，不上传
├── requirements.txt
├── setup.bat
├── start.bat
└── README.md
```

## 常见问题

### 1. 提示找不到 Godot

在控制中心点击“选择 Godot.exe”，重新选择 Godot 4 的可执行文件。路径会保存在 `config/settings.local.json`（该文件已加入 Git 忽略规则，不会上传）。

### 2. 窗口有黑色背景，不透明

先确认使用 Godot 4.4+，并更新显卡驱动。Godot 透明窗口需要逐像素透明支持；不同显卡驱动和桌面合成环境可能表现不同。请把 `logs/godot.log` 和截图发回用于排查。

### 3. 启动后没有看到蛋糕

检查控制中心状态和 `logs/godot.log`。确认 Godot 版本、项目路径正确，并尝试在 Godot 编辑器中打开 `engine/project.godot` 运行项目。

### 4. 鼠标穿透后无法点击蛋糕

这是预期行为。回到控制中心关闭“鼠标穿透”即可恢复交互。

## 开发说明

Godot 场景中的蛋糕由 GDScript 创建 CylinderMesh、SphereMesh、BoxMesh、灯光和粒子节点。后续阶段可以把程序化模型替换为 Blender 制作的 GLB 模型，而不改变 Python 控制中心与 Godot 通信架构。
