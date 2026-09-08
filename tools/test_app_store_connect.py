import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


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

    def test_full_version_iap_is_non_consumable_and_matches_the_app_product_id(self):
        body = asc.full_version_iap_body(
            "app-123",
            asc.FULL_VERSION_PRODUCT_ID,
            asc.FULL_VERSION_NAME,
            asc.FULL_VERSION_REVIEW_NOTE,
        )
        data = body["data"]
        self.assertEqual(data["type"], "inAppPurchases")
        self.assertEqual(
            data["attributes"]["productId"],
            "com.ianhandy.kroma.full_version",
        )
        self.assertEqual(data["attributes"]["inAppPurchaseType"], "NON_CONSUMABLE")
        self.assertNotIn("availableInAllTerritories", data["attributes"])
        self.assertEqual(data["attributes"]["name"], asc.FULL_VERSION_NAME)
        self.assertEqual(data["attributes"]["reviewNote"], asc.FULL_VERSION_REVIEW_NOTE)
        self.assertEqual(
            data["relationships"]["app"],
            {"data": {"type": "apps", "id": "app-123"}},
        )

    def test_repo_metadata_renders_lowercase_copy_and_app_store_limits(self):
        metadata = asc.load_metadata(asc.DEFAULT_METADATA_PATH)
        listing = metadata["listing"]
        self.assertIn("220", listing["description"])
        self.assertIn("3 hearts", listing["description"])
        self.assertIn("first 4 campaign chapters", listing["description"])
        self.assertEqual(listing["description"], listing["description"].lower())
        self.assertLessEqual(len(listing["description"]), 4000)
        self.assertLessEqual(len(listing["keywords"]), 100)

        campaign_path = asc.DEFAULT_METADATA_PATH.parent.parent / "ChromaticOrder" / "Resources" / "campaign.json"
        campaign = json.loads(campaign_path.read_text())
        self.assertEqual(metadata["facts"]["campaign_level_count"], len(campaign["levels"]))

    def test_metadata_templates_fail_on_unknown_variables(self):
        source = json.loads(asc.DEFAULT_METADATA_PATH.read_text())
        source["listing"]["description_paragraphs"] = ["{not_a_real_fact}"]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metadata.json"
            path.write_text(json.dumps(source))
            with self.assertRaisesRegex(asc.AppStoreConnectError, "not_a_real_fact"):
                asc.load_metadata(path)

    def test_metadata_sync_requests_use_environment_contact_and_expected_resources(self):
        metadata = asc.load_metadata(asc.DEFAULT_METADATA_PATH)
        with patch.dict(
            os.environ,
            {"ASC_REVIEW_EMAIL": "review@example.com", "ASC_REVIEW_PHONE": "+15555550123"},
        ):
            requests = asc.metadata_sync_requests(
                metadata, "version-1", "localization-1", "review-1"
            )
        self.assertEqual(
            [request["body"]["data"]["type"] for request in requests],
            [
                "appStoreVersionLocalizations",
                "appStoreVersions",
                "appStoreReviewDetails",
            ],
        )
        review = requests[-1]["body"]["data"]["attributes"]
        self.assertEqual(review["contactEmail"], "review@example.com")
        self.assertEqual(review["contactPhone"], "+15555550123")
        self.assertFalse(review["demoAccountRequired"])


if __name__ == "__main__":
    unittest.main()
