import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from PySide6.QtCore import QObject, QTimer
from PySide6.QtGui import QGuiApplication
from reader import clean_text, chunks, same_text, Task


class ReaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication(['test'])

    def test_book_words_preserved(self):

        original = '21.46:08,188s Verdacht auf Reproiden-Ausbruch im\nRegenwaldgebiet.\n\n»Nate?«, fragte er. Das ist nicht die Venus.'
        cleaned = clean_text(original)
        self.assertEqual(' '.join(original.split()), ' '.join(cleaned.split()))
        self.assertEqual(' '.join(original.split()), ' '.join(chunks(cleaned, 65)))
        self.assertTrue(all(len(c) <= 65 for c in chunks(cleaned, 65)))

    def test_split_at_sentence_boundary(self):
        text = 'Die erste Geschichte endet hier. Die zweite Geschichte beginnt hier.'
        self.assertEqual(chunks(text, 55), ['Die erste Geschichte endet hier.', 'Die zweite Geschichte beginnt hier.'])

    def test_punctuation_only_chunks_do_not_reach_piper(self):
        self.assertEqual(chunks('»«\n\nHallo Welt.\n\n…'), ['Hallo Welt.'])

    def test_failed_page_turn_is_reported(self):
        from reader import Reader
        subject = SimpleNamespace(enabled=True, paused=False, fail=Mock(), scan=Mock())
        with patch('reader.QTimer.singleShot') as timer:
            Reader.page_turn_sent(subject, 1, '', 'Keyboard unavailable')
        subject.fail.assert_called_once()
        timer.assert_not_called()

    def test_error_notification_does_not_set_tray_attention(self):
        from reader import Reader
        subject = SimpleNamespace(update=Mock(), last_error='', tray=Mock())
        with patch('reader.subprocess.Popen') as notify:
            Reader.fail(subject, 'Speech failed')
        subject.tray.showMessage.assert_not_called()
        self.assertEqual(notify.call_args.args[0][0], 'notify-send')

    def test_new_page_is_not_a_duplicate(self):
        self.assertTrue(same_text('Die Venus.\nEin neuer Tag.', 'Die Venus. Ein neuer Tag.'))
        self.assertFalse(same_text('Die Venus. Ein neuer Tag.', 'Der Mars. Eine andere Welt.'))

    def test_cancelled_child_cannot_restart_playback(self):
        app = self.app
        owner = QObject()
        owner.tasks = set()
        callbacks = []
        task = Task(owner, ['/usr/bin/sleep', '30'], lambda *args: callbacks.append(args))
        self.assertTrue(task.proc.waitForStarted(2000))
        task.cancel()
        QTimer.singleShot(10, app.quit)
        app.exec()
        self.assertEqual(callbacks, [])
        self.assertEqual(owner.tasks, set())


    def test_same_text_threshold(self):
        text_a = 'Dies ist eine Seite mit vielen Worten und einem kleinen OCR Fehler.'
        text_b = 'Dies ist eine Seite mit vielen Worten und einem kleinen 0CR Fehler.'
        self.assertTrue(same_text(text_a, text_b, threshold=0.80))
        text_c = 'Völlig anderer Text auf der nächsten Buchseite ohne Ähnlichkeit.'
        self.assertFalse(same_text(text_a, text_c, threshold=0.80))

    def test_playback_still_scans_visible_page(self):
        from reader import Reader
        subject = SimpleNamespace(
            enabled=True, paused=False, scanning=False, menu=Mock(), dialog=None,
            settings={'follow': True}, last_text='Old page', got_window=Mock(),
            is_speaking=lambda: True)
        subject.menu.isVisible.return_value = False
        with patch('reader.Task') as task:
            Reader.scan(subject)
        self.assertTrue(subject.scanning)
        self.assertIs(task.call_args.args[2], subject.got_window)

    def test_cancelling_ocr_releases_scan_flag(self):
        from reader import Reader
        task = Mock()
        subject = SimpleNamespace(
            epoch=0, scanning=True, overlay=Mock(), mpv_command=Mock(),
            speech_tasks=set(), tasks={task})
        with patch('reader.subprocess.run'):
            Reader.stop_speech(subject)
        self.assertFalse(subject.scanning)
        task.cancel.assert_called_once()

    def test_page_change_cancels_old_audio_before_stable_confirmation(self):
        from reader import Reader
        old = 'The previous page has text that should no longer be spoken.'
        new = 'Entirely different words appear after turning to the next chapter.'
        subject = SimpleNamespace(
            scanning=True, last_text=old, candidate='',
            is_speaking=lambda: True, stop_speech=Mock(), update=Mock(),
            scan=Mock(), settings={'highlight': False}, pump_pipeline=Mock())
        with patch('reader.Path.read_text'), patch('reader.visible_ocr', return_value=(new, '')), patch('reader.QTimer.singleShot'):
            Reader.recognized(subject, 0, '', '')
            subject.stop_speech.assert_called_once()
            self.assertEqual(subject.candidate, new)
            subject.pump_pipeline.assert_not_called()
            subject.is_speaking = lambda: False
            Reader.recognized(subject, 0, '', '')
        self.assertEqual(subject.last_text, new)
        self.assertEqual(' '.join(subject.queue), new)
        subject.pump_pipeline.assert_called_once()

    def test_unchanged_page_does_not_interrupt_playback(self):
        from reader import Reader
        text = 'These same words are still visible on the current book page.'
        subject = SimpleNamespace(scanning=True, last_text=text, candidate='', stop_speech=Mock())
        with patch('reader.Path.read_text'), patch('reader.visible_ocr', return_value=(text, '')):
            Reader.recognized(subject, 0, '', '')
        subject.stop_speech.assert_not_called()

    def test_obsolete_page_turn_is_cancelled(self):
        from reader import Reader
        subject = SimpleNamespace(settings={'auto_page_turn': True},
                                  is_kindle_target=lambda: True, update=Mock(),
                                  epoch=1, do_page_turn=Mock())
        with patch('reader.QTimer.singleShot') as timer:
            Reader.on_page_finished(subject)
        subject.epoch += 1
        timer.call_args.args[1]()
        subject.do_page_turn.assert_not_called()

    def test_voices_definition(self):
        from reader import VOICES
        self.assertIn('kokoro-martin', VOICES)
        self.assertIn('kokoro-heart', VOICES)
        self.assertIn('kerstin-fast', VOICES)
        self.assertIn('thorsten-fast', VOICES)
        self.assertNotIn('kerstin', VOICES)
        self.assertNotIn('thorsten', VOICES)
        for key, (label, engine, ref) in VOICES.items():
            self.assertIn(engine, ('kokoro', 'piper', 'qwen'))
            self.assertTrue(len(label) > 0)
            self.assertTrue(len(ref) > 0)

    def test_make_icon(self):
        from reader import make_icon
        for state in ('off', 'on', 'paused'):
            icon = make_icon(state)
            self.assertFalse(icon.isNull())

    def test_custom_area_handling(self):
        import re
        slurp_out = '120,340 800x600\n'
        match = re.match(r'^(\d+),(\d+)\s+(\d+)x(\d+)$', slurp_out.strip())
        self.assertIsNotNone(match)
        x, y, w, h = map(int, match.groups())
        self.assertEqual((x, y, w, h), (120, 340, 800, 600))
        geom = f'{x},{y} {w}x{h}'
        self.assertEqual(geom, '120,340 800x600')

    def test_kindle_area_proportions_and_scaling(self):
        # Window at (100, 100), size (1000, 800)
        win_x, win_y, win_w, win_h = 100, 100, 1000, 800
        # User selected area at (200, 180), size (700, 640)
        sel_x, sel_y, sel_w, sel_h = 200, 180, 700, 640

        # Calculate proportions
        rx = (sel_x - win_x) / win_w  # 0.10
        ry = (sel_y - win_y) / win_h  # 0.10
        rw = sel_w / win_w            # 0.70
        rh = sel_h / win_h            # 0.80

        self.assertAlmostEqual(rx, 0.10)
        self.assertAlmostEqual(ry, 0.10)
        self.assertAlmostEqual(rw, 0.70)
        self.assertAlmostEqual(rh, 0.80)

        # When window is moved to another monitor/position (1920, 0)
        moved_x, moved_y = 1920, 0
        cx = round(moved_x + rx * win_w)
        cy = round(moved_y + ry * win_h)
        cw = round(rw * win_w)
        ch = round(rh * win_h)
        self.assertEqual((cx, cy, cw, ch), (2020, 80, 700, 640))

        # When window is resized to (1200, 900)
        new_w, new_h = 1200, 900
        scaled_cw = round(rw * new_w)
        scaled_ch = round(rh * new_h)
        self.assertEqual((scaled_cw, scaled_ch), (840, 720))

    def test_defaults_include_kindle_area(self):
        from reader import DEFAULTS
        self.assertIn('kindle_area', DEFAULTS)
        self.assertIsNone(DEFAULTS['kindle_area'])


if __name__ == '__main__':
    unittest.main()
