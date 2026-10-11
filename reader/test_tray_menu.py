import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from reader import Reader


class TrayMenuTests(unittest.TestCase):
    """Launch & Bind reads the tray menu over D-Bus; choices must be real, checkable actions."""

    def test_choice_menu_marks_current_and_calls_handler(self):
        menu, handler = Mock(), Mock()
        made = []
        def add_action(label):
            action = Mock(label=label)
            made.append(action)
            return action
        menu.addAction.side_effect = add_action
        with patch('reader.QActionGroup'):
            actions = Reader.fill_choice_menu(None, menu, [('de', 'German · Deutsch'), ('en', 'English')], 'en', handler)
        menu.clear.assert_called_once()
        self.assertEqual(list(actions), ['de', 'en'])
        actions['de'].setChecked.assert_called_with(False)
        actions['en'].setChecked.assert_called_with(True)
        callback = actions['de'].triggered.connect.call_args.args[0]
        callback()
        handler.assert_called_once_with('de')

    def test_menu_setting_reports_invalid_choice(self):
        subject = SimpleNamespace(configure_settings=Mock(side_effect=ValueError('Unknown language')), fail=Mock())
        Reader.menu_setting(subject, 'language', 'xx')
        subject.fail.assert_called_once_with('Unknown language')

    def test_rebuild_only_when_choices_change(self):
        subject = SimpleNamespace(settings=dict(language='de', voice='kokoro-martin', audio_output='auto'),
                                  choice_signature=None, voice_menu=Mock(), language_menu=Mock(), output_menu=Mock(),
                                  voice_language=lambda: 'de', fill_choice_menu=Mock(return_value={}), set_voice=Mock())
        with patch('reader.available_voices', return_value={'kokoro-martin': ('Martin', 'kokoro', 'martin')}), \
             patch('reader.outputs', return_value=[dict(value='auto', label='System default')]):
            Reader.refresh_choice_menus(subject)
            Reader.refresh_choice_menus(subject)
            self.assertEqual(subject.fill_choice_menu.call_count, 3)
            subject.settings['language'] = 'en'
            Reader.refresh_choice_menus(subject)
            self.assertEqual(subject.fill_choice_menu.call_count, 6)


if __name__ == '__main__':
    unittest.main()


class StartStopTests(unittest.TestCase):
    """▶ Start, Stop and the tray actions call set_enabled(..., notify=True)."""

    def subject(self, enabled=False):
        from reader import DEFAULTS
        return SimpleNamespace(provider_status='', installing_kokoro=False, settings=dict(DEFAULTS),
                               preview_original=None, testing_voice=False, enabled=enabled, paused=False,
                               stop_speech=Mock(), tasks=set(), update=Mock(), timer=Mock(),
                               kokoro_worker=Mock(), translation_worker=Mock(), overlay=Mock(), scan=Mock())

    def test_start_with_notification_starts_scanning(self):
        subject = self.subject()
        with patch('reader.voice_is_available', return_value=True), patch('reader.subprocess.Popen') as popen, \
             patch('reader.QTimer.singleShot') as single_shot:
            Reader.set_enabled(subject, True, notify=True)
        self.assertTrue(subject.enabled)
        subject.timer.start.assert_called_once()
        single_shot.assert_called_once()
        self.assertEqual(popen.call_args.args[0][0], 'notify-send')

    def test_stop_with_notification_stops_scanning(self):
        subject = self.subject(enabled=True)
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as folder, patch('reader.subprocess.Popen'), patch('reader.RUNTIME', Path(folder)):
            Reader.set_enabled(subject, False, notify=True)
        self.assertFalse(subject.enabled)
        subject.timer.stop.assert_called_once()
