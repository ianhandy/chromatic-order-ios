import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name("app_store_connect.py")
SPEC = importlib.util.spec_from_file_location("app_store_connect", SCRIPT)
assert SPEC and SPEC.loader
asc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(asc)


class AppStoreConnectTests(unittest.TestCase):
    def test_base64url_omits_padding(self):
        self.assertEqual(asc.b64url(b"hello"), "aGVsbG8")

    def test_der_ecdsa_signature_becomes_fixed_width_jws_signature(self):
        r = bytes.fromhex("01" * 32)
        s = bytes.fromhex("80" + "02" * 31)
        der = b"\x30\x45\x02\x20" + r + b"\x02\x21\x00" + s
        raw = asc.der_signature_to_raw(der)
        self.assertEqual(raw, r + s)
        self.assertEqual(len(raw), 64)

    def test_relation_uses_json_api_shape(self):
        self.assertEqual(
            asc.relation("apps", "123"),
            {"data": {"type": "apps", "id": "123"}},
        )


if __name__ == "__main__":
    unittest.main()
