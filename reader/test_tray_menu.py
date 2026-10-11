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
