from pathlib import Path
import tempfile
import unittest

from tool.reference import prepare_zh_en_callback_oracle as prepare


class CombinedOracleNativePayloadTests(unittest.TestCase):
    def test_rejects_versioned_and_node_native_names(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("module.node", "libexample.so.1", "program.exe"):
                path = root / name
                path.write_bytes(b"not identified by magic")
                with self.subTest(name=name):
                    self.assertTrue(prepare._is_native_payload(path))

    def test_rejects_compiled_magic_without_a_native_suffix(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, magic in (
                ("extension", b"\x7fELF"),
                ("archive.data", b"!<arch>\n"),
                ("portable.bin", b"MZ"),
                ("module.data", b"\x00asm"),
            ):
                path = root / name
                path.write_bytes(magic + b"synthetic")
                with self.subTest(name=name):
                    self.assertTrue(prepare._is_native_payload(path))

    def test_allows_a_pure_python_source_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "module.py"
            path.write_text("value = 1\n", encoding="utf-8")
            self.assertFalse(prepare._is_native_payload(path))


if __name__ == "__main__":
    unittest.main()
