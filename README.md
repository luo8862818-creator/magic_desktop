# Magic Desktop

Windows 桌面 3D 悬浮动画原型。当前版本完成第一阶段：Python 控制中心 + Godot 实时 3D 透明桌面窗口。

## 当前实现

- Python + PySide6 控制中心。
- Godot 4 实时 3D 场景：双层巧克力蛋糕、奶油裱花、淋面滴落、糖珠、彩色糖针、三支烛光、立体星星、飘带与环境粒子。
- 无边框、透明背景、始终置顶的桌面窗口。
- 蛋糕默认以 8°/秒缓慢自动旋转并轻微浮动，蜡烛火焰、星星和泰迪熊持续轻柔动态变化。
- 电影感柔光、冷暖轮廓光、金属餐盘装饰与轻微辉光。
- 点击蛋糕触发小型彩色星光反馈，不会缩放或放大整个蛋糕。
- 鼠标拖动窗口。
- 鼠标穿透开关：开启后鼠标操作会传递给桌面下方窗口。
- 自定义祝福文字、旋转速度。
- 背景音乐选择、播放、停止和音量控制（MP3 / OGG / WAV）。
- 点击触发原创合成提示音。
- 自动检测 `tools/godot/` 目录中的 Godot 4 Windows GUI 可执行文件；也保留手动选择路径作为备用。
- Python 与 Godot 通过本机 UDP（127.0.0.1）通信。

## 音频与视频导出

- 控制中心可选择 MP3 / OGG / WAV 背景音乐，播放、停止并调整音量。
- 点击蛋糕或控制中心触发惊喜时，会播放程序生成的原创提示音。
- 支持导出 5 / 8 / 10 / 15 秒 MP4 或 GIF；MP4 默认 1920×1080、30 FPS，导出区会明确显示时长和总帧数。
- MP4 可包含已选择的背景音乐；GIF 不包含音频。
- 导出过程先由 Godot Movie Maker 渲染 AVI，再由 imageio-ffmpeg 转换为 MP4 / GIF。

## 本轮视觉升级

- 蛋糕视觉改为草莓奶油主题：粉色淋面、修正截面方向的立体奶油裱花、草莓与糖珠装饰。
- 增加泰迪熊摆件、礼物盒、漂浮星星、彩色丝带和小型星光点击反馈；点击不再缩放整个蛋糕，避免白色餐盘突然放大。
- 控制中心改为可滚动布局，增加控件高度与卡片间距，修复输入框、标签和滑块挤压重叠的问题。
- 悬浮窗口调整为 1120×630（16:9），控制中心调整为 700×900；镜头重新拉远并为顶部装饰和底部祝福语预留安全边距。

## 当前版本尚未实现

Blender 高精度模型、复杂音效编辑器和 EXE 安装包属于后续阶段。本版本不把这些未完成能力标记为已实现。

## 环境要求

- Windows 10/11（建议 64 位）。
- Python 3.11 或更高版本。
- Godot Engine 4.4 或更高版本的 Standard Windows 64-bit 版本。只需下载并解压，不需要安装。
- 支持桌面透明窗口的显卡驱动。透明效果可用性会受到显卡驱动和 Windows 桌面合成环境影响。

Godot 官方下载：https://godotengine.org/download/windows/

## 第一次运行

1. 下载或克隆仓库。
2. 安装 Python 3.11+。
3. 从 Godot 官网下载 Godot 4.4+ Standard Windows 64-bit 压缩包并解压。
4. 将解压得到的 GUI 版文件（名称类似 `Godot_v4.5-stable_win64.exe`）放入项目的 `tools/godot/` 目录。不要只放 console 版本。
5. 双击 `setup.bat`，创建虚拟环境并安装 PySide6、imageio-ffmpeg（用于 MP4/GIF 编码）。
6. 双击 `start.bat`，打开 Magic Desktop 控制中心。
7. 程序会自动识别 `tools/godot/` 中唯一的 GUI 版 Godot exe，点击“启动桌面动画”即可。若放入多个版本，或自动识别失败，可点击“选择...”手动指定。

首次运行新版场景前，建议先双击 `check_engine.bat`，检查 Python 语法和 Godot 项目/GDScript 是否能正常加载；检查通过后再运行 `start.bat`。

Godot 下载地址：https://godotengine.org/download/windows/

**说明：** 当前阶段放入的是 Godot 编辑器发行版 exe，程序通过它运行项目；这不是最终交付时的独立导出运行程序。最终发布版会再改为内置 Godot 导出运行时。

## 控制方式

| 操作 | 效果 |
|---|---|
| 鼠标左键拖动蛋糕区域 | 移动桌面悬浮窗口 |
| 鼠标左键点击蛋糕 | 触发小型彩色星光，不缩放蛋糕主体 |
| 控制中心修改祝福语 | 更新 3D 文字 |
| 控制中心调整旋转速度 | 实时调整旋转速度 |
| 选择背景音乐 | 播放 MP3 / OGG / WAV 音乐并调整音量 |
| 导出 MP4 | 输出 5 / 8 / 10 / 15 秒 1920×1080 视频，可包含背景音乐 |
| 导出 GIF | 输出 5 / 8 / 10 / 15 秒 960×540 循环动画，不含声音 |
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
├── tools/
│   └── godot/             # 将下载的 Godot Windows GUI exe 放在这里（本地文件，不上传）
├── logs/                 # 运行时生成，不上传
├── output/               # 后续导出目录，不上传
├── requirements.txt
├── setup.bat
├── start.bat
├── check_engine.bat
└── README.md
```

## 常见问题

### 1. 提示找不到 Godot

确认已将 Godot 4 Windows GUI 版 exe 放入 `tools/godot/`，文件名以 `Godot` 开头且扩展名为 `.exe`。如果目录中有多个版本，请在控制中心点击“选择...”手动指定。手动选择的路径会保存在 `config/settings.local.json`（该文件已加入 Git 忽略规则，不会上传）。

### 2. 窗口有黑色背景，不透明

先确认使用 Godot 4.4+，并更新显卡驱动。Godot 透明窗口需要逐像素透明支持；不同显卡驱动和桌面合成环境可能表现不同。请把 `logs/godot.log` 和截图发回用于排查。

### 3. 启动后没有看到蛋糕

检查控制中心状态和 `logs/godot.log`。确认 Godot 版本、项目路径正确，并尝试在 Godot 编辑器中打开 `engine/project.godot` 运行项目。

### 4. 鼠标穿透后无法点击蛋糕

这是预期行为。回到控制中心关闭“鼠标穿透”即可恢复交互。

## 开发说明

Godot 场景中的蛋糕与泰迪熊摆件由 GDScript 创建 CylinderMesh、SphereMesh、BoxMesh、SurfaceTool 网格、灯光和粒子节点。后续阶段可以把程序化模型替换为 Blender 制作的 GLB 模型，而不改变 Python 控制中心与 Godot 通信架构。
