import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_ORIGINAL_STDOUT = sys.stdout
_ORIGINAL_STDERR = sys.stderr
from app import (
    UIMessageQueue,
    ONLINE_TRANSLATOR_MAPPING,
    _TranslationLogParser,
    _clean_control_chars,
    _compose_output_format,
    _decode_subprocess_line,
    _find_available_local_port,
    _line_passes_filter,
    _normalize_openai_base_url,
    _set_command_option,
    _split_command_template,
    _split_output_format,
    _strip_ansi,
    _stream_proc_to_queue,
)
sys.stdout = _ORIGINAL_STDOUT
sys.stderr = _ORIGINAL_STDERR


class AppFormattingTests(unittest.TestCase):
    def test_output_format_round_trip(self):
        self.assertEqual(_compose_output_format("双语", "SRT", True), "双语SRT")
        self.assertEqual(_compose_output_format("目标", "LRC", False), "原文LRC")
        self.assertEqual(_split_output_format("双语SRT"), ("双语", "SRT"))
        self.assertEqual(_split_output_format("目标LRC"), ("目标", "LRC"))
        self.assertEqual(_split_output_format("unknown"), ("unknown", ""))

    def test_command_option_replaces_separate_and_equals_forms(self):
        command = ["tool", "-m", "old", "--port=1"]
        _set_command_option(command, ("--model", "-m"), "--model", "new")
        _set_command_option(command, ("--port",), "--port", "2")
        _set_command_option(command, ("--backend",), "--backend", "qwen")
        self.assertEqual(command, ["tool", "-m", "new", "--port=2", "--backend", "qwen"])

    def test_command_template_preserves_quoted_argument(self):
        tokens = _split_command_template('tool --model "a model.gguf"')
        self.assertEqual(tokens, ["tool", "--model", "a model.gguf"])

    def test_log_text_cleaning_and_filtering(self):
        self.assertEqual(_strip_ansi("\x1b[31merror\x1b[0m"), "error")
        self.assertEqual(_clean_control_chars("abc\rthis is the longest line\x00"), "this is the longest line")
        self.assertEqual(_clean_control_chars("yg2|message"), "message")
        self.assertTrue(_line_passes_filter("plain", "ERROR+"))
        self.assertFalse(_line_passes_filter("[INFO] hello", "WARNING+"))
        self.assertTrue(_line_passes_filter("[ERROR] boom", "WARNING+"))

    def test_subprocess_decoding_falls_back_to_gbk(self):
        self.assertEqual(_decode_subprocess_line("中文".encode("gbk")), "中文")
        self.assertEqual(_decode_subprocess_line(b"ascii"), "ascii")

    def test_available_port_is_in_valid_range(self):
        port = _find_available_local_port()
        self.assertGreater(port, 0)
        self.assertLessEqual(port, 65535)


class MessageQueueAndLogParserTests(unittest.TestCase):
    def test_message_queue_logs_clean_text_drains_and_completes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "app.log"
            queue = UIMessageQueue(str(log_path))
            queue.put("detail", "\x1b[32mhello\x1b[0m")
            self.assertEqual(queue.drain(), [("detail", "\x1b[32mhello\x1b[0m")])
            self.assertEqual(log_path.read_text(encoding="utf-8"), "hello\n")
            self.assertFalse(queue.is_completion_ready())
            queue.set_completion_flag()
            queue.put_completion_sentinel()
            target, text = queue.drain()[0]
            self.assertTrue(queue.is_completion_ready())
            self.assertTrue(queue.is_completion_entry(target))
            self.assertEqual(text, "")

    def test_translation_log_parser_batches_destinations(self):
        parser = _TranslationLogParser()
        self.assertEqual(parser.feed("v--1-[A]"), [])
        self.assertEqual(parser.feed("> Src: 原文"), [])
        self.assertEqual(parser.feed("> Dst: 译文"), [])
        output = parser.feed("ordinary")
        self.assertEqual(json.loads(output[0]), {"id": 1, "dst": "译文"})
        self.assertEqual(output[1], "ordinary")

    def test_translation_log_parser_preserves_interrupted_record(self):
        parser = _TranslationLogParser()
        parser.feed("v--2")
        self.assertEqual(parser.feed("unexpected"), ["v--2", "unexpected"])

    def test_stream_process_forwards_clean_nonempty_lines(self):
        class Proc:
            stdout = io.BytesIO(b"\x1b[31merror\x1b[0m\n\n")

        class Queue:
            def __init__(self):
                self.items = []

            def put(self, target, text):
                self.items.append((target, text))

        queue = Queue()
        _stream_proc_to_queue(Proc(), queue, label="worker")
        self.assertEqual(queue.items, [("detail", "[worker] error")])


class OpenAITranslatorUrlTests(unittest.TestCase):
    """「测试API」按钮与真实翻译必须推导出同一个 base URL。

    回归背景：测试按钮曾无条件拼接 ``/v1/models``，对火山方舟
    ``/api/plan/v3``、``/api/v3`` 这类自带版本段的地址会拼成
    ``.../api/plan/v3/v1/models`` 并误报 404，而真实翻译其实是通的。
    """

    def test_versioned_base_urls_are_kept_as_is(self):
        for url in (
            "https://ark.cn-beijing.volces.com/api/v3",
            "https://ark.cn-beijing.volces.com/api/plan/v3",
            "https://generativelanguage.googleapis.com/v1beta/openai",
        ):
            with self.subTest(url=url):
                self.assertEqual(_normalize_openai_base_url(url), url)

    def test_plain_hosts_get_v1_appended(self):
        cases = {
            "https://api.deepseek.com": "https://api.deepseek.com/v1",
            "https://api.moonshot.cn": "https://api.moonshot.cn/v1",
            "https://api.openai.com": "https://api.openai.com/v1",
            "http://localhost:11434": "http://localhost:11434/v1",
            "https://dashscope.aliyuncs.com/compatible-mode":
                "https://dashscope.aliyuncs.com/compatible-mode/v1",
        }
        for given, expected in cases.items():
            with self.subTest(url=given):
                self.assertEqual(_normalize_openai_base_url(given), expected)

    def test_pasted_endpoint_urls_are_reduced_to_base(self):
        cases = {
            "https://open.bigmodel.cn/api/paas/v4/chat/completions":
                "https://open.bigmodel.cn/api/paas/v4",
            "https://api.deepseek.com/v1/models": "https://api.deepseek.com/v1",
        }
        for given, expected in cases.items():
            with self.subTest(url=given):
                self.assertEqual(_normalize_openai_base_url(given), expected)

    def test_trailing_slash_and_blank_input(self):
        self.assertEqual(
            _normalize_openai_base_url("https://api.deepseek.com/"),
            "https://api.deepseek.com/v1",
        )
        self.assertEqual(_normalize_openai_base_url(""), "")
        self.assertEqual(_normalize_openai_base_url(None), "")

    def test_agent_plan_url_from_bug_report(self):
        endpoint = _normalize_openai_base_url(
            "https://ark.cn-beijing.volces.com/api/plan/v3"
        )
        self.assertEqual(
            endpoint + "/models",
            "https://ark.cn-beijing.volces.com/api/plan/v3/models",
        )
        self.assertEqual(
            endpoint + "/chat/completions",
            "https://ark.cn-beijing.volces.com/api/plan/v3/chat/completions",
        )
        self.assertNotIn("/v1/", endpoint + "/models")

    def test_presets_never_add_v1_to_a_versioned_host(self):
        for name in ("豆包", "豆包 (Agent Plan)"):
            with self.subTest(preset=name):
                endpoint = _normalize_openai_base_url(ONLINE_TRANSLATOR_MAPPING[name])
                self.assertNotIn("/v1", endpoint)
                self.assertIn("/api/", endpoint)


if __name__ == "__main__":
    unittest.main()
