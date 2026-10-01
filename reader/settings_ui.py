"""Compact Omarchy-style settings and integrated manual for Simple Reader."""
import tomllib
from pathlib import Path

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QFormLayout,
                              QLabel, QPushButton, QScrollArea, QStackedWidget)

MANUAL = [
    ('1. Reading & Tray Controls', [
        'Focus the window containing the text, then click Start reader in the Omarchy bar popup. Existing reader shortcuts remain available.',
        'Right-click the tray icon for voice, speed, Read again, settings and quit.',
        'Middle-click the tray icon to pause or resume. Off stops speech and reader-owned work.']),
    ('2. Voice, Language & Speed', [
        'Choose a local voice and select German or English as the text language.',
        'Kokoro is the default neural engine; Piper Fast is the lower-latency option. Qwen voices can need a longer warm-up.',
        'Set reading speed from 0.6× to 2×. Save applies your changes; Cancel discards uncommitted settings.']),
    ('3. Continuous Reading & Kindle', [
        'Enable automatic reading to follow changes to the active window or page.',
        'Kindle cropping skips the toolbar, margins and progress bar.',
        'Automatic page turning advances the Kindle page after narration finishes.',
        'Manual page changes stop the old speech and resume after the new text settles.']),
    ('4. Reading Area & Highlighting', [
        'Select area lets you choose a precise region. The settings dialog closes before selection.',
        'Reset returns to the full active window.',
        'Highlight the passage being read follows the current speech chunk. It hides when another window has focus.',
        'Moving or resizing the source window clears old highlight positions until the next capture.']),
    ('5. Troubleshooting & Local Processing', [
        'No speech: check that narration is on, the correct window is focused, and the selected local voice is installed.',
        'Unwanted text: select a smaller reading area or enable Kindle cropping.',
        'Wrong pronunciation: check the text language and try another voice.',
        'OCR and speech processing run locally. Turning narration off stops reader-owned capture and speech processes.'])
]


def theme_colors():
    """Use the current Omarchy palette without changing shell or desktop settings."""
    colors = {'background': '#101315', 'foreground': '#cacccc', 'accent': '#cacccc'}
    path = Path.home() / '.local/state/omarchy/current/theme/colors.toml'
    try:
        values = tomllib.loads(path.read_text())
        for key in colors:
            value = values.get(key)
            if isinstance(value, str) and QColor(value).isValid():
                colors[key] = QColor(value).name()
    except (OSError, ValueError):
        pass
    return colors


def section_heading(text):
    label = QLabel(text)
    label.setObjectName('sectionHeading')
    label.setWordWrap(True)
    return label


def build_settings_layout(dialog):
    dialog.setObjectName('ocrvoxSettings')
    dialog.setWindowFlag(Qt.WindowType.Tool, True)
    screen = dialog.screen()
    available = screen.availableGeometry() if screen else None
    width = min(488, available.width() - 40) if available else 488
    height = min(760, available.height() - 80) if available else 760
    # Fixed size hints keep Hyprland from stretching the dialog into a tiled slot.
    dialog.setFixedSize(max(320, width), max(320, height))
    outer = QVBoxLayout(dialog)
    outer.setContentsMargins(14, 14, 14, 14)
    outer.setSpacing(12)
    header = QHBoxLayout()
    title = QLabel('Simple Reader')
    title.setObjectName('pluginTitle')
    manual_button = QPushButton('📖 User Manual')
    manual_button.setCheckable(True)
    manual_button.setFixedHeight(24)
    header.addWidget(title)
    header.addStretch()
    header.addWidget(manual_button)
    outer.addLayout(header)
    subtitle = QLabel('A little room to listen.')
    subtitle.setObjectName('subtitle')
    outer.addWidget(subtitle)
    pages = QStackedWidget()
    outer.addWidget(pages)
    settings_page = QWidget()
    form = QFormLayout(settings_page)
    form.setContentsMargins(0, 0, 0, 0)
    form.setHorizontalSpacing(8)
    form.setVerticalSpacing(12)
    form.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.AllNonFixedFieldsGrow)
    form.setRowWrapPolicy(QFormLayout.RowWrapPolicy.WrapAllRows)

    def scrolled(widget):
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        scroll.setWidget(widget)
        return scroll

    settings_scroll = scrolled(settings_page)
    pages.addWidget(settings_scroll)
    manual_page = QWidget()
    manual_layout = QVBoxLayout(manual_page)
    manual_layout.setContentsMargins(0, 0, 0, 0)
    manual_layout.setSpacing(10)

    def back_button():
        button = QPushButton('← Back to Reading Controls')
        button.clicked.connect(lambda: manual_button.setChecked(False))
        return button

    manual_layout.addWidget(back_button())
    for title, bullets in MANUAL:
        card = QWidget()
        card.setObjectName('manualCard')
        layout = QVBoxLayout(card)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(4)
        layout.addWidget(section_heading(title))
        body = QLabel('\n'.join('• ' + text for text in bullets))
        body.setObjectName('manualBody')
        body.setTextFormat(Qt.TextFormat.PlainText)
        body.setWordWrap(True)
        layout.addWidget(body)
        manual_layout.addWidget(card)
    manual_layout.addWidget(back_button())
    manual_layout.addStretch()
    manual_scroll = scrolled(manual_page)
    pages.addWidget(manual_scroll)

    def show_manual(checked):
        pages.setCurrentIndex(1 if checked else 0)
        manual_button.setText('✕ Close Manual' if checked else '📖 User Manual')
        (manual_scroll if checked else settings_scroll).verticalScrollBar().setValue(0)

    manual_button.toggled.connect(show_manual)
    last_colors = None

    def refresh_theme():
        nonlocal last_colors
        colors = theme_colors()
        if colors == last_colors:
            return
        last_colors = colors
        bg, fg, accent = (colors[k] for k in ('background', 'foreground', 'accent'))
        dialog.setStyleSheet(f'''
            QDialog#ocrvoxSettings, QWidget {{ background: {bg}; color: {fg};
                font-family: "JetBrainsMono Nerd Font"; font-size: 12px; }}
            QScrollArea, QStackedWidget {{ border: none; }}
            QLabel#pluginTitle {{ color: {accent}; font-size: 14px; font-weight: bold; }}
            QLabel#sectionHeading {{ color: {accent}; font-size: 11px; font-weight: bold; }}
            QLabel#subtitle {{ color: {fg}; }}
            QWidget#manualCard {{ background: rgba({QColor(fg).red()}, {QColor(fg).green()}, {QColor(fg).blue()}, 13);
                border: 1px solid rgba({QColor(fg).red()}, {QColor(fg).green()}, {QColor(fg).blue()}, 38); border-radius: 6px; }}
            QWidget#manualCard QLabel {{ background: transparent; border: none; }}
            QLabel#manualBody {{ font-size: 10px; }}
            QPushButton, QComboBox, QDoubleSpinBox {{ padding: 6px 10px;
                border: 1px solid {fg}; border-radius: 0px; }}
            QPushButton:hover, QComboBox:hover, QDoubleSpinBox:hover {{ border-color: {accent}; }}
            QPushButton:checked {{ background: {accent}; color: {bg}; }}
            QPushButton:disabled {{ color: #707880; border-color: #707880; }}
            QComboBox QAbstractItemView {{ background: {bg}; color: {fg};
                selection-background-color: {accent}; selection-color: {bg}; }}
            QCheckBox {{ spacing: 8px; }}
        ''')

    refresh_theme()
    timer = QTimer(dialog)
    timer.setInterval(1500)
    timer.timeout.connect(refresh_theme)
    timer.start()
    return form
