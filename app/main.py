from __future__ import annotations

import json
import logging
import os
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QCloseEvent, QFont
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
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
        "rotation_speed": 24,
        "birthday_text": "Happy Birthday",
        "window_width": 640,
        "window_height": 520,
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
    except (OSError, json.JSONDecodeError) as exc:
        logging.exception("Failed to read settings: %s", exc)
    return defaults


def save_settings(settings: dict[str, Any]) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(
        json.dumps(settings, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


class MagicDesktopWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.settings = load_settings()
        self.detected_godot = find_godot_executable(str(self.settings.get("godot_exe", "")))
        self.godot_process: subprocess.Popen[bytes] | None = None
        self.godot_log_handle: Any = None
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.passthrough_enabled = False

        self.setWindowTitle("Magic Desktop | 控制中心")
        self.setMinimumSize(500, 570)
        self.resize(540, 620)
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
        root = QVBoxLayout(central)
        root.setContentsMargins(26, 24, 26, 24)
        root.setSpacing(16)

        header = QVBoxLayout()
        title = QLabel("MAGIC DESKTOP")
        title.setObjectName("appTitle")
        subtitle = QLabel("实时 3D 桌面动画控制中心")
        subtitle.setObjectName("subtitle")
        header.addWidget(title)
        header.addWidget(subtitle)
        root.addLayout(header)

        status_card = QFrame()
        status_card.setObjectName("card")
        status_layout = QVBoxLayout(status_card)
        status_layout.setContentsMargins(16, 14, 16, 14)
        status_layout.setSpacing(6)
        status_caption = QLabel("ENGINE STATUS")
        status_caption.setObjectName("sectionCaption")
        self.status_label = QLabel("正在初始化...")
        self.status_label.setObjectName("status")
        self.status_label.setWordWrap(True)
        status_layout.addWidget(status_caption)
        status_layout.addWidget(self.status_label)
        root.addWidget(status_card)

        godot_card = QFrame()
        godot_card.setObjectName("card")
        godot_layout = QVBoxLayout(godot_card)
        godot_layout.setContentsMargins(16, 14, 16, 14)
        godot_layout.setSpacing(10)
        godot_caption = QLabel("GODOT ENGINE")
        godot_caption.setObjectName("sectionCaption")
        godot_layout.addWidget(godot_caption)

        path_row = QHBoxLayout()
        self.godot_path_input = QLineEdit(str(self.settings.get("godot_exe", "")))
        self.godot_path_input.setPlaceholderText("选择 Godot 4.x 可执行文件")
        choose_button = QPushButton("选择...")
        choose_button.setObjectName("secondaryButton")
        choose_button.clicked.connect(self._choose_godot)
        path_row.addWidget(self.godot_path_input, 1)
        path_row.addWidget(choose_button)
        godot_layout.addLayout(path_row)

        engine_buttons = QHBoxLayout()
        self.start_button = QPushButton("启动桌面动画")
        self.start_button.setObjectName("primaryButton")
        self.start_button.clicked.connect(self._start_engine)
        self.stop_button = QPushButton("停止引擎")
        self.stop_button.setObjectName("dangerButton")
        self.stop_button.clicked.connect(self._stop_engine)
        engine_buttons.addWidget(self.start_button, 1)
        engine_buttons.addWidget(self.stop_button, 1)
        godot_layout.addLayout(engine_buttons)
        root.addWidget(godot_card)

        controls_card = QFrame()
        controls_card.setObjectName("card")
        controls = QVBoxLayout(controls_card)
        controls.setContentsMargins(16, 14, 16, 14)
        controls.setSpacing(12)
        controls_caption = QLabel("ANIMATION CONTROLS")
        controls_caption.setObjectName("sectionCaption")
        controls.addWidget(controls_caption)

        text_label = QLabel("祝福文字")
        self.text_input = QLineEdit(str(self.settings.get("birthday_text", "Happy Birthday")))
        self.text_input.setPlaceholderText("输入要显示的文字")
        self.text_input.setMaxLength(32)
        text_row = QHBoxLayout()
        text_row.addWidget(self.text_input, 1)
        apply_text_button = QPushButton("应用文字")
        apply_text_button.setObjectName("secondaryButton")
        apply_text_button.clicked.connect(self._apply_text)
        text_row.addWidget(apply_text_button)
        controls.addWidget(text_label)
        controls.addLayout(text_row)

        speed_row = QHBoxLayout()
        speed_label = QLabel("旋转速度")
        self.speed_value_label = QLabel()
        self.speed_value_label.setObjectName("valueLabel")
        speed_row.addWidget(speed_label)
        speed_row.addStretch(1)
        speed_row.addWidget(self.speed_value_label)
        controls.addLayout(speed_row)

        self.speed_slider = QSlider(Qt.Orientation.Horizontal)
        self.speed_slider.setRange(0, 120)
        self.speed_slider.setValue(int(self.settings.get("rotation_speed", 24)))
        self.speed_slider.valueChanged.connect(self._rotation_speed_changed)
        controls.addWidget(self.speed_slider)
        self._rotation_speed_changed(self.speed_slider.value())

        root.addWidget(controls_card)

        actions_card = QFrame()
        actions_card.setObjectName("card")
        actions = QVBoxLayout(actions_card)
        actions.setContentsMargins(16, 14, 16, 14)
        actions.setSpacing(10)
        actions_caption = QLabel("DESKTOP ACTIONS")
        actions_caption.setObjectName("sectionCaption")
        actions.addWidget(actions_caption)

        row_one = QHBoxLayout()
        show_button = QPushButton("显示动画")
        show_button.setObjectName("secondaryButton")
        show_button.clicked.connect(lambda: self._send_command({"action": "show"}))
        hide_button = QPushButton("隐藏动画")
        hide_button.setObjectName("secondaryButton")
        hide_button.clicked.connect(lambda: self._send_command({"action": "hide"}))
        row_one.addWidget(show_button)
        row_one.addWidget(hide_button)
        actions.addLayout(row_one)

        row_two = QHBoxLayout()
        burst_button = QPushButton("触发惊喜特效")
        burst_button.setObjectName("secondaryButton")
        burst_button.clicked.connect(lambda: self._send_command({"action": "burst"}))
        self.passthrough_button = QPushButton("鼠标穿透：关闭")
        self.passthrough_button.setObjectName("secondaryButton")
        self.passthrough_button.setCheckable(True)
        self.passthrough_button.toggled.connect(self._toggle_passthrough)
        row_two.addWidget(burst_button)
        row_two.addWidget(self.passthrough_button)
        actions.addLayout(row_two)
        root.addWidget(actions_card)

        footer = QLabel(
            "提示：开启鼠标穿透后，蛋糕不会接收点击和拖动。\n"
            "点击蛋糕可触发弹跳与粒子效果；拖动蛋糕区域可移动窗口。"
        )
        footer.setObjectName("footer")
        footer.setWordWrap(True)
        root.addWidget(footer)
        root.addStretch(1)

        self.setCentralWidget(central)

    def _apply_style(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow, QWidget {
                background: #10141d;
                color: #e8edf5;
                font-family: "Microsoft YaHei UI", "Segoe UI";
                font-size: 13px;
            }
            QLabel#appTitle {
                color: #f4f7fb;
                font-size: 25px;
                font-weight: 800;
                letter-spacing: 2px;
            }
            QLabel#subtitle { color: #8f9bad; font-size: 13px; }
            QFrame#card {
                background: #191f2b;
                border: 1px solid #293244;
                border-radius: 12px;
            }
            QLabel#sectionCaption {
                color: #7e9bc5;
                font-size: 10px;
                font-weight: 800;
                letter-spacing: 1.5px;
            }
            QLabel#status { color: #cbd5e1; font-size: 13px; }
            QLabel#valueLabel { color: #9fc5ff; font-weight: 700; }
            QLabel#footer { color: #7f8b9d; font-size: 11px; }
            QLineEdit {
                background: #0f141d;
                border: 1px solid #354156;
                border-radius: 7px;
                padding: 9px 10px;
                color: #f3f6fb;
                selection-background-color: #426ca8;
            }
            QLineEdit:focus { border: 1px solid #6a9ce5; }
            QPushButton {
                border: 0;
                border-radius: 8px;
                padding: 10px 12px;
                font-weight: 600;
                min-height: 18px;
            }
            QPushButton#primaryButton { background: #3478d4; color: white; }
            QPushButton#primaryButton:hover { background: #4389e8; }
            QPushButton#dangerButton { background: #492630; color: #ffc7d0; }
            QPushButton#dangerButton:hover { background: #65303d; }
            QPushButton#secondaryButton { background: #293447; color: #dce7f8; }
            QPushButton#secondaryButton:hover { background: #35445d; }
            QPushButton#secondaryButton:checked { background: #8a5b25; color: #fff1d8; }
            QSlider::groove:horizontal {
                height: 5px; background: #303b4d; border-radius: 2px;
            }
            QSlider::sub-page:horizontal { background: #4f91e8; border-radius: 2px; }
            QSlider::handle:horizontal {
                background: #dceaff; width: 15px; margin: -5px 0;
                border-radius: 7px;
            }
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
                "请将 Godot 4.x Windows GUI 版 exe 放入以下目录：\\n"
                f"{GODOT_DIR}\\n\\n"
                "文件名应以 Godot 开头，例如 Godot_v4.5-stable_win64.exe。\\n"
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
