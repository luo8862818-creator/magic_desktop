from __future__ import annotations

import json
import logging
import os
import socket
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, QTimer, QThread, Signal
from PySide6.QtGui import QCloseEvent, QFont
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QScrollArea,
    QMessageBox,
    QPushButton,
    QSlider,
    QVBoxLayout,
    QWidget,
)

ROOT_DIR = Path(__file__).resolve().parents[1]
ENGINE_DIR = ROOT_DIR / "engine"
GODOT_DIR = ROOT_DIR / "tools" / "godot"
DEFAULT_CONFIG_FILE = ROOT_DIR / "config" / "settings.json"
CONFIG_FILE = ROOT_DIR / "config" / "settings.local.json"
LOG_DIR = ROOT_DIR / "logs"
LOG_FILE = LOG_DIR / "app.log"
IPC_HOST = "127.0.0.1"
IPC_PORT = 49261


def find_godot_executable(configured_path: str = "") -> Path | None:
    """Find a Godot 4 Windows executable bundled in tools/godot.

    A previously selected local path takes priority while it still exists.
    If the folder contains exactly one GUI executable, use it automatically.
    Console builds are only used as a fallback.
    """
    configured = Path(configured_path.strip().strip('"')) if configured_path.strip() else None
    if configured and configured.is_file():
        return configured

    if not GODOT_DIR.is_dir():
        return None

    candidates = sorted(
        path for path in GODOT_DIR.glob("Godot*.exe")
        if path.is_file()
    )
    gui_candidates = [
        path for path in candidates
        if "console" not in path.stem.lower()
    ]
    preferred = gui_candidates or candidates
    if len(preferred) == 1:
        return preferred[0]
    return None


def configure_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(LOG_FILE, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )


def load_settings() -> dict[str, Any]:
    defaults: dict[str, Any] = {
        "godot_exe": "",
        "rotation_speed": 8,
        "birthday_text": "Happy Birthday",
        "window_width": 1120,
        "window_height": 630,
        "music_file": "",
        "music_volume": 0.55,
        "export_duration_seconds": 8,
    }
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    source_file = CONFIG_FILE if CONFIG_FILE.exists() else DEFAULT_CONFIG_FILE
    if not source_file.exists():
        save_settings(defaults)
        return defaults
    try:
        loaded = json.loads(source_file.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            defaults.update(loaded)
            # Migrate the old 24°/s starter value to a calmer default once.
            if (
                int(defaults.get("rotation_speed", 8)) == 24
                and loaded.get("rotation_speed_profile") != "slow-v2"
            ):
                defaults["rotation_speed"] = 8
                defaults["rotation_speed_profile"] = "slow-v2"
                save_settings(defaults)
    except (OSError, json.JSONDecodeError) as exc:
        logging.exception("Failed to read settings: %s", exc)
    return defaults


def save_settings(settings: dict[str, Any]) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(
        json.dumps(settings, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


class ExportWorker(QThread):
    progress = Signal(str)
    result_ready = Signal(bool, str)

    def __init__(
        self,
        godot_exe: Path,
        engine_dir: Path,
        output_path: Path,
        export_format: str,
        music_file: str,
        music_volume: float,
        birthday_text: str,
        rotation_speed: int,
        duration_seconds: int,
    ) -> None:
        super().__init__()
        self.godot_exe = godot_exe
        self.engine_dir = engine_dir
        self.output_path = output_path
        self.export_format = export_format
        self.music_file = music_file
        self.music_volume = music_volume
        self.birthday_text = birthday_text
        self.rotation_speed = rotation_speed
        self.duration_seconds = max(1, int(duration_seconds))
        self.fps = 30
        self.frame_count = self.duration_seconds * self.fps

    def run(self) -> None:
        temp_dir = self.output_path.parent / f".{self.output_path.stem}_render_tmp"
        frame_path = temp_dir / "frame.png"
        frame_pattern = temp_dir / "frame%08d.png"
        audio_path = temp_dir / "frame.wav"

        try:
            self.output_path.parent.mkdir(parents=True, exist_ok=True)
            if temp_dir.exists():
                shutil.rmtree(temp_dir)
            temp_dir.mkdir(parents=True, exist_ok=True)

            env = os.environ.copy()
            env["MAGIC_DESKTOP_EXPORT"] = "1"
            env["MAGIC_DESKTOP_MUSIC"] = self.music_file
            env["MAGIC_DESKTOP_MUSIC_VOLUME"] = str(self.music_volume)
            env["MAGIC_DESKTOP_TEXT"] = self.birthday_text
            env["MAGIC_DESKTOP_SPEED"] = str(self.rotation_speed)

            self.progress.emit(
                f"正在无损渲染 {self.duration_seconds} 秒 3D 动画"
                f"（{self.frame_count} 帧，1920×1080，30 FPS）..."
            )
            render_command = [
                str(self.godot_exe),
                "--path", str(self.engine_dir),
                "--write-movie", str(frame_path),
                "--fixed-fps", str(self.fps),
                "--quit-after", str(self.frame_count),
                "--resolution", "1920x1080",
            ]
            render_result = subprocess.run(
                render_command,
                cwd=str(self.engine_dir),
                env=env,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=1800,
            )
            if render_result.returncode != 0:
                details = (render_result.stderr or render_result.stdout or "")[-5000:]
                raise RuntimeError(
                    "Godot 无损帧渲染失败。\n"
                    f"退出代码：{render_result.returncode}\n{details}"
                )

            rendered_frames = list(temp_dir.glob("frame*.png"))
            if len(rendered_frames) != self.frame_count:
                raise RuntimeError(
                    "Godot 输出帧数不完整："
                    f"期望 {self.frame_count} 帧，实际 {len(rendered_frames)} 帧。"
                    "请检查 logs/godot.log。"
                )

            self.progress.emit(
                f"无损渲染完成（{len(rendered_frames)} 帧），正在编码最终文件..."
            )
            import imageio_ffmpeg

            ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
            duration_text = str(self.duration_seconds)
            video_filter = (
                "scale=1920:1080:force_original_aspect_ratio=decrease,"
                "pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x0b1020,"
                "setsar=1"
            )

            if self.export_format == "mp4":
                encode_command = [
                    ffmpeg_exe, "-y",
                    "-framerate", str(self.fps),
                    "-start_number", "0",
                    "-i", str(frame_pattern),
                ]
                has_audio = audio_path.is_file() and audio_path.stat().st_size > 44
                if has_audio:
                    encode_command.extend(["-i", str(audio_path)])

                encode_command.extend([
                    "-map", "0:v:0",
                    "-vf", video_filter,
                    "-r", str(self.fps),
                    "-t", duration_text,
                    "-c:v", "libx264",
                    "-preset", "slow",
                    "-crf", "16",
                    "-profile:v", "high",
                    "-pix_fmt", "yuv420p",
                ])
                if has_audio:
                    encode_command.extend([
                        "-map", "1:a:0",
                        "-c:a", "aac",
                        "-b:a", "192k",
                        "-shortest",
                    ])
                else:
                    encode_command.append("-an")

                encode_command.extend([
                    "-movflags", "+faststart",
                    str(self.output_path),
                ])
            else:
                gif_filter = (
                    "fps=15,scale=960:540:flags=lanczos,"
                    "split[s0][s1];"
                    "[s0]palettegen=stats_mode=diff[p];"
                    "[s1][p]paletteuse=dither=bayer"
                )
                encode_command = [
                    ffmpeg_exe, "-y",
                    "-framerate", str(self.fps),
                    "-start_number", "0",
                    "-i", str(frame_pattern),
                    "-an",
                    "-t", duration_text,
                    "-filter_complex", gif_filter,
                    "-loop", "0",
                    str(self.output_path),
                ]

            encode_result = subprocess.run(
                encode_command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=1200,
            )
            if encode_result.returncode != 0:
                details = (encode_result.stderr or encode_result.stdout or "")[-5000:]
                raise RuntimeError(f"FFmpeg 编码失败。\n{details}")
            if not self.output_path.is_file() or self.output_path.stat().st_size == 0:
                raise RuntimeError("编码结束，但没有生成有效的导出文件。")

            self.result_ready.emit(True, str(self.output_path))
        except Exception as exc:
            self.result_ready.emit(False, str(exc))
        finally:
            try:
                if temp_dir.exists():
                    shutil.rmtree(temp_dir)
            except OSError:
                pass


class MagicDesktopWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.settings = load_settings()
        self.detected_godot = find_godot_executable(str(self.settings.get("godot_exe", "")))
        self.godot_process: subprocess.Popen[bytes] | None = None
        self.godot_log_handle: Any = None
        self.export_worker: ExportWorker | None = None
        self.music_playing = False
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.passthrough_enabled = False

        self.setWindowTitle("Magic Desktop | 控制中心")
        self.setMinimumSize(620, 760)
        self.resize(700, 900)
        self._build_ui()
        self._apply_style()

        self.process_timer = QTimer(self)
        self.process_timer.setInterval(700)
        self.process_timer.timeout.connect(self._check_process)
        self.process_timer.start()

        if self.detected_godot:
            self.godot_path_input.setText(str(self.detected_godot))
            self._set_status(
                f"已自动识别 Godot：{self.detected_godot.name}。可以启动桌面动画。",
                "success",
            )
        else:
            self._set_status(
                f"未找到 Godot。请将 Godot 4.x Windows GUI 版 exe 放入：{GODOT_DIR}",
                "muted",
            )

    def _build_ui(self) -> None:
        central = QWidget()
        outer = QVBoxLayout(central)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        scroll = QScrollArea()
        scroll.setObjectName("mainScroll")
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        content = QWidget()
        root = QVBoxLayout(content)
        root.setContentsMargins(26, 24, 26, 24)
        root.setSpacing(16)

        header = QVBoxLayout()
        header.setSpacing(5)
        title = QLabel("MAGIC DESKTOP")
        title.setObjectName("appTitle")
        subtitle = QLabel("PREMIUM 3D DESKTOP EXPERIENCE  ·  实时动画控制中心")
        subtitle.setObjectName("subtitle")
        header.addWidget(title)
        header.addWidget(subtitle)
        root.addLayout(header)

        status_card = QFrame()
        status_card.setObjectName("card")
        status_layout = QVBoxLayout(status_card)
        status_layout.setContentsMargins(17, 14, 17, 14)
        status_layout.setSpacing(8)
        status_caption = QLabel("ENGINE STATUS")
        status_caption.setObjectName("sectionCaption")
        self.status_label = QLabel("正在初始化...")
        self.status_label.setObjectName("status")
        self.status_label.setMinimumHeight(22)
        self.status_label.setWordWrap(True)
        status_layout.addWidget(status_caption)
        status_layout.addWidget(self.status_label)
        root.addWidget(status_card)

        godot_card = QFrame()
        godot_card.setObjectName("card")
        godot_layout = QVBoxLayout(godot_card)
        godot_layout.setContentsMargins(17, 15, 17, 16)
        godot_layout.setSpacing(11)
        godot_caption = QLabel("GODOT ENGINE")
        godot_caption.setObjectName("sectionCaption")
        godot_layout.addWidget(godot_caption)

        path_row = QHBoxLayout()
        path_row.setSpacing(10)
        self.godot_path_input = QLineEdit(str(self.settings.get("godot_exe", "")))
        self.godot_path_input.setPlaceholderText("自动识别 tools/godot/，也可手动选择")
        self.godot_path_input.setMinimumHeight(42)
        choose_button = QPushButton("选择引擎")
        choose_button.setObjectName("secondaryButton")
        choose_button.setMinimumWidth(104)
        choose_button.setMinimumHeight(42)
        choose_button.clicked.connect(self._choose_godot)
        path_row.addWidget(self.godot_path_input, 1)
        path_row.addWidget(choose_button)
        godot_layout.addLayout(path_row)

        engine_buttons = QHBoxLayout()
        engine_buttons.setSpacing(10)
        self.start_button = QPushButton("启动桌面动画")
        self.start_button.setObjectName("primaryButton")
        self.start_button.setMinimumHeight(46)
        self.start_button.clicked.connect(self._start_engine)
        self.stop_button = QPushButton("停止引擎")
        self.stop_button.setObjectName("dangerButton")
        self.stop_button.setMinimumHeight(46)
        self.stop_button.clicked.connect(self._stop_engine)
        engine_buttons.addWidget(self.start_button, 1)
        engine_buttons.addWidget(self.stop_button, 1)
        godot_layout.addLayout(engine_buttons)
        root.addWidget(godot_card)

        controls_card = QFrame()
        controls_card.setObjectName("card")
        controls = QVBoxLayout(controls_card)
        controls.setContentsMargins(17, 15, 17, 16)
        controls.setSpacing(10)
        controls_caption = QLabel("PERSONALIZE YOUR SCENE")
        controls_caption.setObjectName("sectionCaption")
        controls.addWidget(controls_caption)

        text_label = QLabel("生日祝福文字")
        text_label.setObjectName("fieldLabel")
        self.text_input = QLineEdit(str(self.settings.get("birthday_text", "Happy Birthday")))
        self.text_input.setPlaceholderText("例如：Happy Birthday!")
        self.text_input.setMaxLength(32)
        self.text_input.setMinimumHeight(42)

        text_row = QHBoxLayout()
        text_row.setSpacing(10)
        text_row.addWidget(self.text_input, 1)
        apply_text_button = QPushButton("应用文字")
        apply_text_button.setObjectName("secondaryButton")
        apply_text_button.setMinimumWidth(104)
        apply_text_button.setMinimumHeight(42)
        apply_text_button.clicked.connect(self._apply_text)
        text_row.addWidget(apply_text_button)
        controls.addWidget(text_label)
        controls.addLayout(text_row)

        speed_header = QHBoxLayout()
        speed_header.setSpacing(8)
        speed_label = QLabel("蛋糕旋转速度")
        speed_label.setObjectName("fieldLabel")
        self.speed_value_label = QLabel()
        self.speed_value_label.setObjectName("valueLabel")
        speed_header.addWidget(speed_label)
        speed_header.addStretch(1)
        speed_header.addWidget(self.speed_value_label)
        controls.addLayout(speed_header)

        self.speed_slider = QSlider(Qt.Orientation.Horizontal)
        self.speed_slider.setRange(0, 60)
        self.speed_slider.setValue(int(self.settings.get("rotation_speed", 12)))
        self.speed_slider.setMinimumHeight(24)
        self.speed_slider.valueChanged.connect(self._rotation_speed_changed)
        controls.addWidget(self.speed_slider)
        self._rotation_speed_changed(self.speed_slider.value())
        root.addWidget(controls_card)

        audio_card = QFrame()
        audio_card.setObjectName("card")
        audio_layout = QVBoxLayout(audio_card)
        audio_layout.setContentsMargins(17, 15, 17, 16)
        audio_layout.setSpacing(10)
        audio_caption = QLabel("MUSIC & SOUND")
        audio_caption.setObjectName("sectionCaption")
        audio_layout.addWidget(audio_caption)

        music_file_row = QHBoxLayout()
        music_file_row.setSpacing(10)
        self.music_path_label = QLabel("未选择背景音乐")
        self.music_path_label.setObjectName("fileLabel")
        self.music_path_label.setWordWrap(True)
        self.music_path_label.setMinimumHeight(34)
        self.music_path_label.setText(
            Path(str(self.settings.get("music_file", ""))).name
            if self.settings.get("music_file")
            else "未选择背景音乐（支持 MP3 / OGG / WAV）"
        )
        choose_music_button = QPushButton("选择音乐")
        choose_music_button.setObjectName("secondaryButton")
        choose_music_button.setMinimumWidth(104)
        choose_music_button.setMinimumHeight(42)
        choose_music_button.clicked.connect(self._choose_music)
        music_file_row.addWidget(self.music_path_label, 1)
        music_file_row.addWidget(choose_music_button)
        audio_layout.addLayout(music_file_row)

        music_buttons = QHBoxLayout()
        music_buttons.setSpacing(10)
        play_music_button = QPushButton("播放音乐")
        play_music_button.setObjectName("secondaryButton")
        play_music_button.setMinimumHeight(42)
        play_music_button.clicked.connect(self._play_music)
        stop_music_button = QPushButton("停止音乐")
        stop_music_button.setObjectName("secondaryButton")
        stop_music_button.setMinimumHeight(42)
        stop_music_button.clicked.connect(self._stop_music)
        music_buttons.addWidget(play_music_button, 1)
        music_buttons.addWidget(stop_music_button, 1)
        audio_layout.addLayout(music_buttons)

        volume_header = QHBoxLayout()
        volume_label = QLabel("背景音乐音量")
        volume_label.setObjectName("fieldLabel")
        self.music_volume_value = QLabel()
        self.music_volume_value.setObjectName("valueLabel")
        volume_header.addWidget(volume_label)
        volume_header.addStretch(1)
        volume_header.addWidget(self.music_volume_value)
        audio_layout.addLayout(volume_header)

        self.music_volume_slider = QSlider(Qt.Orientation.Horizontal)
        self.music_volume_slider.setRange(0, 100)
        self.music_volume_slider.setValue(
            int(float(self.settings.get("music_volume", 0.55)) * 100)
        )
        self.music_volume_slider.setMinimumHeight(24)
        self.music_volume_slider.valueChanged.connect(self._music_volume_changed)
        audio_layout.addWidget(self.music_volume_slider)
        self._music_volume_changed(self.music_volume_slider.value())
        root.addWidget(audio_card)

        export_card = QFrame()
        export_card.setObjectName("card")
        export_layout = QVBoxLayout(export_card)
        export_layout.setContentsMargins(17, 15, 17, 16)
        export_layout.setSpacing(10)
        export_caption = QLabel("VIDEO EXPORT")
        export_caption.setObjectName("sectionCaption")
        export_layout.addWidget(export_caption)

        export_settings_row = QHBoxLayout()
        export_settings_row.setSpacing(12)
        export_resolution_label = QLabel("1920 × 1080  ·  30 FPS")
        export_resolution_label.setObjectName("fieldLabel")
        self.duration_combo = QComboBox()
        self.duration_combo.addItem("5 秒", 5)
        self.duration_combo.addItem("8 秒（推荐）", 8)
        self.duration_combo.addItem("10 秒", 10)
        self.duration_combo.addItem("15 秒", 15)
        self.duration_combo.setMinimumHeight(38)
        saved_duration = int(self.settings.get("export_duration_seconds", 8))
        saved_index = self.duration_combo.findData(saved_duration)
        self.duration_combo.setCurrentIndex(saved_index if saved_index >= 0 else 1)
        self.duration_combo.currentIndexChanged.connect(self._update_export_hint)
        export_settings_row.addWidget(export_resolution_label)
        export_settings_row.addStretch(1)
        export_settings_row.addWidget(QLabel("时长"))
        export_settings_row.addWidget(self.duration_combo)
        export_layout.addLayout(export_settings_row)

        self.export_hint = QLabel()
        self.export_hint.setObjectName("fieldLabel")
        export_layout.addWidget(self.export_hint)
        self._update_export_hint()

        export_buttons = QHBoxLayout()
        export_buttons.setSpacing(10)
        self.export_mp4_button = QPushButton("导出 MP4")
        self.export_mp4_button.setObjectName("primaryButton")
        self.export_mp4_button.setMinimumHeight(46)
        self.export_mp4_button.clicked.connect(lambda: self._start_export("mp4"))
        self.export_gif_button = QPushButton("导出 GIF")
        self.export_gif_button.setObjectName("secondaryButton")
        self.export_gif_button.setMinimumHeight(46)
        self.export_gif_button.clicked.connect(lambda: self._start_export("gif"))
        export_buttons.addWidget(self.export_mp4_button, 1)
        export_buttons.addWidget(self.export_gif_button, 1)
        export_layout.addLayout(export_buttons)

        export_note = QLabel("MP4：高清画质，可选背景音乐。GIF：无声循环动画。导出时长以此处选择为准。")
        export_note.setObjectName("footer")
        export_note.setWordWrap(True)
        export_layout.addWidget(export_note)
        root.addWidget(export_card)

        actions_card = QFrame()
        actions_card.setObjectName("card")
        actions = QVBoxLayout(actions_card)
        actions.setContentsMargins(17, 15, 17, 16)
        actions.setSpacing(11)
        actions_caption = QLabel("DESKTOP INTERACTIONS")
        actions_caption.setObjectName("sectionCaption")
        actions.addWidget(actions_caption)

        row_one = QHBoxLayout()
        row_one.setSpacing(10)
        show_button = QPushButton("显示动画")
        show_button.setObjectName("secondaryButton")
        show_button.setMinimumHeight(46)
        show_button.clicked.connect(lambda: self._send_command({"action": "show"}))
        hide_button = QPushButton("隐藏动画")
        hide_button.setObjectName("secondaryButton")
        hide_button.setMinimumHeight(46)
        hide_button.clicked.connect(lambda: self._send_command({"action": "hide"}))
        row_one.addWidget(show_button, 1)
        row_one.addWidget(hide_button, 1)
        actions.addLayout(row_one)

        row_two = QHBoxLayout()
        row_two.setSpacing(10)
        burst_button = QPushButton("触发惊喜特效")
        burst_button.setObjectName("secondaryButton")
        burst_button.setMinimumHeight(46)
        burst_button.clicked.connect(lambda: self._send_command({"action": "burst"}))
        self.passthrough_button = QPushButton("鼠标穿透：关闭")
        self.passthrough_button.setObjectName("secondaryButton")
        self.passthrough_button.setCheckable(True)
        self.passthrough_button.setMinimumHeight(46)
        self.passthrough_button.toggled.connect(self._toggle_passthrough)
        row_two.addWidget(burst_button, 1)
        row_two.addWidget(self.passthrough_button, 1)
        actions.addLayout(row_two)
        root.addWidget(actions_card)

        footer = QLabel(
            "交互提示  ·  蛋糕会自动缓慢旋转；点击触发彩色星光，按住拖动可移动悬浮窗口。\n"
            "开启鼠标穿透后，鼠标操作将直接传递给桌面下方的应用。"
        )
        footer.setObjectName("footer")
        footer.setWordWrap(True)
        footer.setMinimumHeight(36)
        root.addWidget(footer)
        root.addStretch(1)

        scroll.setWidget(content)
        outer.addWidget(scroll)
        self.setCentralWidget(central)

    def _apply_style(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow, QWidget {
                background: #0d111b;
                color: #e9eef8;
                font-family: "Microsoft YaHei UI", "Segoe UI";
                font-size: 13px;
            }
            QScrollArea#mainScroll { background: #0d111b; border: 0; }
            QScrollArea#mainScroll QWidget { background: transparent; }
            QLabel#appTitle {
                color: #f5f7fc;
                font-size: 27px;
                font-weight: 900;
                letter-spacing: 2px;
            }
            QLabel#subtitle { color: #8494ad; font-size: 11px; }
            QFrame#card {
                background: #171f2d;
                border: 1px solid #2a3850;
                border-radius: 13px;
            }
            QLabel#sectionCaption {
                color: #86b5f2;
                font-size: 10px;
                font-weight: 800;
                letter-spacing: 1.6px;
            }
            QLabel#fieldLabel { color: #c3cede; font-size: 12px; font-weight: 600; }
            QLabel#status { color: #d5e2f4; font-size: 13px; }
            QLabel#valueLabel { color: #9cc9ff; font-size: 12px; font-weight: 800; }
            QLabel#fileLabel { color: #aebbd0; font-size: 12px; }
            QLabel#footer { color: #8492a8; font-size: 11px; }
            QLineEdit {
                background: #0e1521;
                border: 1px solid #354660;
                border-radius: 8px;
                padding: 0 12px;
                color: #f3f6fc;
                selection-background-color: #426ca8;
            }
            QLineEdit:focus { border: 1px solid #6ea9f5; }
            QPushButton {
                border: 0;
                border-radius: 9px;
                padding: 9px 13px;
                font-weight: 700;
                min-height: 22px;
            }
            QPushButton#primaryButton { background: #347edb; color: white; }
            QPushButton#primaryButton:hover { background: #4a91ed; }
            QPushButton#dangerButton { background: #482a38; color: #ffd4df; }
            QPushButton#dangerButton:hover { background: #633448; }
            QPushButton#secondaryButton { background: #29384f; color: #e0eafa; }
            QPushButton#secondaryButton:hover { background: #354967; }
            QPushButton#secondaryButton:checked { background: #8a602d; color: #fff1d8; }
            QComboBox {
                background: #0e1521;
                color: #e9eef8;
                border: 1px solid #354660;
                border-radius: 8px;
                padding: 5px 10px;
                min-width: 100px;
            }
            QComboBox QAbstractItemView {
                background: #172131;
                color: #e9eef8;
                selection-background-color: #347edb;
                border: 1px solid #354660;
            }
            QSlider::groove:horizontal {
                height: 6px; background: #2d3b50; border-radius: 3px;
            }
            QSlider::sub-page:horizontal { background: #5d9eea; border-radius: 3px; }
            QSlider::handle:horizontal {
                background: #e7f1ff; width: 16px; margin: -6px 0;
                border-radius: 8px;
            }
            QScrollBar:vertical {
                background: #101724; width: 9px; margin: 2px;
                border-radius: 4px;
            }
            QScrollBar::handle:vertical {
                background: #3a4d68; min-height: 28px; border-radius: 4px;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
            """
        )

    def _set_status(self, message: str, level: str = "normal") -> None:
        colors = {
            "normal": "#cbd5e1",
            "muted": "#8f9bad",
            "success": "#83d6aa",
            "warning": "#f2c879",
            "error": "#ff8795",
        }
        color = colors.get(level, colors["normal"])
        self.status_label.setStyleSheet(f"color: {color};")
        self.status_label.setText(message)

    def _choose_music(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择背景音乐",
            str(Path.home()),
            "Audio files (*.mp3 *.ogg *.wav);;All files (*.*)",
        )
        if not path:
            return

        self.settings["music_file"] = path
        save_settings(self.settings)
        self.music_path_label.setText(Path(path).name)
        if self.godot_process and self.godot_process.poll() is None:
            self._send_command({"action": "set_music", "path": path})
        self._set_status("背景音乐已选择。点击“播放音乐”试听。", "success")

    def _play_music(self) -> None:
        path = str(self.settings.get("music_file", "")).strip()
        if not path or not Path(path).is_file():
            QMessageBox.information(self, "尚未选择音乐", "请先选择 MP3、OGG 或 WAV 音频文件。")
            return
        if not self.godot_process or self.godot_process.poll() is not None:
            QMessageBox.information(self, "3D 引擎未启动", "请先启动桌面动画，再播放背景音乐。")
            return
        self._send_command({"action": "set_music", "path": path})
        self._send_command({
            "action": "set_music_volume",
            "value": self.music_volume_slider.value() / 100.0,
        })
        self._send_command({"action": "play_music"})
        self.music_playing = True
        self._set_status("背景音乐正在播放。", "success")

    def _stop_music(self) -> None:
        self._send_command({"action": "stop_music"})
        self.music_playing = False
        self._set_status("背景音乐已停止。", "muted")

    def _music_volume_changed(self, value: int) -> None:
        self.music_volume_value.setText(f"{value}%")
        volume = value / 100.0
        self.settings["music_volume"] = volume
        save_settings(self.settings)
        if self.godot_process and self.godot_process.poll() is None:
            self._send_command({"action": "set_music_volume", "value": volume})

    def _update_export_hint(self, _index: int = -1) -> None:
        if not hasattr(self, "duration_combo"):
            return
        duration = int(self.duration_combo.currentData() or 8)
        frames = duration * 30
        self.export_hint.setText(
            f"本次导出：{duration} 秒  ·  {frames} 帧  ·  1920 × 1080  ·  30 FPS"
        )
        self.settings["export_duration_seconds"] = duration
        save_settings(self.settings)

    def _start_export(self, export_format: str) -> None:
        if self.export_worker and self.export_worker.isRunning():
            QMessageBox.information(self, "正在导出", "当前导出任务完成后才能开始下一次导出。")
            return

        godot_exe = find_godot_executable(self.godot_path_input.text())
        if not godot_exe:
            QMessageBox.warning(
                self,
                "未找到 Godot",
                f"请确认 Godot 4.x GUI 版 exe 位于：\n{GODOT_DIR}",
            )
            return

        output_dir = ROOT_DIR / "output"
        output_dir.mkdir(parents=True, exist_ok=True)
        default_name = "MagicDesktop_Animation.mp4" if export_format == "mp4" else "MagicDesktop_Animation.gif"
        file_filter = "MP4 video (*.mp4)" if export_format == "mp4" else "GIF animation (*.gif)"
        output, _ = QFileDialog.getSaveFileName(
            self,
            "导出桌面动画",
            str(output_dir / default_name),
            file_filter,
        )
        if not output:
            return

        output_path = Path(output)
        expected_suffix = f".{export_format}"
        if output_path.suffix.lower() != expected_suffix:
            output_path = output_path.with_suffix(expected_suffix)

        try:
            import imageio_ffmpeg  # noqa: F401
        except ImportError:
            QMessageBox.critical(
                self,
                "缺少视频编码组件",
                "请在项目目录执行 setup.bat，安装 imageio-ffmpeg 后再导出。",
            )
            return

        self.export_worker = ExportWorker(
            godot_exe=godot_exe,
            engine_dir=ENGINE_DIR,
            output_path=output_path,
            export_format=export_format,
            music_file=str(self.settings.get("music_file", "")),
            music_volume=float(self.music_volume_slider.value() / 100.0),
            birthday_text=self.text_input.text().strip() or "Happy Birthday",
            rotation_speed=self.speed_slider.value(),
            duration_seconds=int(self.duration_combo.currentData() or 8),
        )
        self.export_worker.progress.connect(
            lambda message: self._set_status(message, "warning")
        )
        self.export_worker.result_ready.connect(self._on_export_result)
        self.export_worker.finished.connect(self._clear_export_worker)
        self.export_mp4_button.setEnabled(False)
        self.export_gif_button.setEnabled(False)
        self._set_status("正在准备导出任务...", "warning")
        self.export_worker.start()

    def _on_export_result(self, success: bool, message: str) -> None:
        if success:
            self._set_status(f"导出完成：{message}", "success")
            QMessageBox.information(self, "导出完成", f"文件已生成：\n{message}")
        else:
            self._set_status("导出失败，请查看错误信息。", "error")
            QMessageBox.critical(self, "导出失败", message)

    def _clear_export_worker(self) -> None:
        self.export_mp4_button.setEnabled(True)
        self.export_gif_button.setEnabled(True)
        self.export_worker = None

    def _choose_godot(self) -> None:
        current = self.godot_path_input.text().strip()
        start_dir = str(Path(current).parent) if current else str(Path.home())
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择 Godot 4 可执行文件",
            start_dir,
            "Godot executable (Godot*.exe);;Executable (*.exe);;All files (*.*)",
        )
        if path:
            self.godot_path_input.setText(path)
            self.settings["godot_exe"] = path
            save_settings(self.settings)
            self._set_status("Godot 路径已保存。", "success")

    def _start_engine(self) -> None:
        if self.godot_process and self.godot_process.poll() is None:
            self._send_command({"action": "show"})
            self._set_status("3D 引擎已经在运行。", "success")
            return

        godot_exe = find_godot_executable(self.godot_path_input.text())
        if not godot_exe:
            GODOT_DIR.mkdir(parents=True, exist_ok=True)
            QMessageBox.warning(
                self,
                "未找到 Godot 4",
                "请将 Godot 4.x Windows GUI 版 exe 放入以下目录：\n"
                f"{GODOT_DIR}\n\n"
                "文件名应以 Godot 开头，例如 Godot_v4.5-stable_win64.exe。\n"
                "如果目录中有多个版本，请点击“选择...”手动指定。",
            )
            return
        self.godot_path_input.setText(str(godot_exe))
        if not (ENGINE_DIR / "project.godot").is_file():
            QMessageBox.critical(self, "项目文件缺失", f"找不到：{ENGINE_DIR / 'project.godot'}")
            return

        self.settings["godot_exe"] = str(godot_exe)
        self.settings["rotation_speed"] = self.speed_slider.value()
        self.settings["birthday_text"] = self.text_input.text()
        save_settings(self.settings)

        LOG_DIR.mkdir(parents=True, exist_ok=True)
        try:
            self.godot_log_handle = LOG_FILE.with_name("godot.log").open("a", encoding="utf-8")
            env = os.environ.copy()
            env["MAGIC_DESKTOP_PORT"] = str(IPC_PORT)
            env["MAGIC_DESKTOP_MUSIC"] = str(self.settings.get("music_file", ""))
            env["MAGIC_DESKTOP_MUSIC_VOLUME"] = str(self.settings.get("music_volume", 0.55))
            env["MAGIC_DESKTOP_TEXT"] = self.text_input.text().strip() or "Happy Birthday"
            env["MAGIC_DESKTOP_SPEED"] = str(self.speed_slider.value())
            creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
            self.godot_process = subprocess.Popen(
                [str(godot_exe), "--path", str(ENGINE_DIR)],
                cwd=str(ENGINE_DIR),
                env=env,
                stdout=self.godot_log_handle,
                stderr=subprocess.STDOUT,
                creationflags=creationflags,
            )
        except OSError as exc:
            logging.exception("Could not start Godot")
            self._close_godot_log()
            QMessageBox.critical(self, "启动失败", f"无法启动 Godot：\n{exc}")
            self._set_status("Godot 启动失败，请检查路径和日志。", "error")
            return

        logging.info("Started Godot process pid=%s", self.godot_process.pid)
        self._set_status("正在启动 Godot 3D 场景...", "warning")
        QTimer.singleShot(1600, self._send_initial_settings)

    def _send_initial_settings(self) -> None:
        if not self.godot_process or self.godot_process.poll() is not None:
            return
        self._send_command(
            {
                "action": "set_rotation_speed",
                "value": self.speed_slider.value(),
            }
        )
        self._send_command(
            {
                "action": "set_text",
                "value": self.text_input.text().strip() or "Happy Birthday",
            }
        )
        self._send_command({
            "action": "set_music_volume",
            "value": self.music_volume_slider.value() / 100.0,
        })
        music_file = str(self.settings.get("music_file", "")).strip()
        if music_file and Path(music_file).is_file():
            self._send_command({"action": "set_music", "path": music_file})
        self._set_status("3D 桌面动画运行中。", "success")

    def _send_command(self, payload: dict[str, Any]) -> None:
        if not self.godot_process or self.godot_process.poll() is not None:
            self._set_status("3D 引擎尚未启动。", "warning")
            return
        try:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.udp_socket.sendto(data, (IPC_HOST, IPC_PORT))
        except OSError as exc:
            logging.exception("IPC send failed: %s", exc)
            self._set_status(f"发送控制指令失败：{exc}", "error")

    def _apply_text(self) -> None:
        text = self.text_input.text().strip()
        if not text:
            QMessageBox.information(self, "提示", "祝福文字不能为空。")
            return
        self.settings["birthday_text"] = text
        save_settings(self.settings)
        self._send_command({"action": "set_text", "value": text})

    def _rotation_speed_changed(self, value: int) -> None:
        self.speed_value_label.setText(f"{value}° / 秒")
        self.settings["rotation_speed"] = value
        save_settings(self.settings)
        if self.godot_process and self.godot_process.poll() is None:
            self._send_command({"action": "set_rotation_speed", "value": value})

    def _toggle_passthrough(self, enabled: bool) -> None:
        self.passthrough_enabled = enabled
        self.passthrough_button.setText(
            "鼠标穿透：开启" if enabled else "鼠标穿透：关闭"
        )
        self._send_command({"action": "set_passthrough", "enabled": enabled})

    def _stop_engine(self) -> None:
        process = self.godot_process
        if not process or process.poll() is not None:
            self.godot_process = None
            self._close_godot_log()
            self._set_status("3D 引擎当前未运行。", "muted")
            return

        self._set_status("正在关闭 3D 引擎...", "warning")
        self._send_command({"action": "quit"})
        QTimer.singleShot(1800, self._force_stop_if_needed)

    def _force_stop_if_needed(self) -> None:
        process = self.godot_process
        if process and process.poll() is None:
            logging.warning("Godot did not exit gracefully; terminating process.")
            process.terminate()
            QTimer.singleShot(1200, self._kill_if_needed)
        else:
            self._finish_process()

    def _kill_if_needed(self) -> None:
        process = self.godot_process
        if process and process.poll() is None:
            process.kill()
        self._finish_process()

    def _check_process(self) -> None:
        if self.godot_process and self.godot_process.poll() is not None:
            code = self.godot_process.returncode
            logging.info("Godot process exited with code %s", code)
            self._finish_process()
            if code == 0:
                self._set_status("3D 引擎已正常退出。", "muted")
            else:
                self._set_status(
                    f"Godot 已退出，退出代码：{code}。请检查 logs/godot.log。",
                    "error",
                )

    def _finish_process(self) -> None:
        self.godot_process = None
        self._close_godot_log()

    def _close_godot_log(self) -> None:
        if self.godot_log_handle:
            try:
                self.godot_log_handle.close()
            except OSError:
                pass
            self.godot_log_handle = None

    def closeEvent(self, event: QCloseEvent) -> None:
        if self.export_worker and self.export_worker.isRunning():
            QMessageBox.warning(
                self,
                "视频正在导出",
                "请等待当前 MP4/GIF 导出完成后再关闭控制中心。",
            )
            event.ignore()
            return

        process = self.godot_process
        if process and process.poll() is None:
            try:
                self.udp_socket.sendto(
                    b'{"action":"quit"}',
                    (IPC_HOST, IPC_PORT),
                )
                process.wait(timeout=2.5)
            except (OSError, subprocess.TimeoutExpired):
                process.terminate()
                try:
                    process.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    process.kill()
            self._finish_process()
        self.udp_socket.close()
        event.accept()


def main() -> int:
    configure_logging()
    app = QApplication(sys.argv)
    app.setApplicationName("Magic Desktop")
    app.setFont(QFont("Microsoft YaHei UI", 10))
    window = MagicDesktopWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
