#!/usr/bin/env python3
"""Small, dependency-free App Store Connect release helper.

Credentials are read from the environment and are never written to disk:

    ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_PRIVATE_KEY_PATH=... \
      tools/app_store_connect.py status

Write operations are dry-run unless --apply is present. Sending a version to
App Review additionally requires --confirm-submit.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


API_BASE = "https://api.appstoreconnect.apple.com"
DEFAULT_BUNDLE_ID = "com.ianhandy.kroma"
STREAK_LEADERBOARD_ID = "com.ianhandy.kroma.daily_streak"


class AppStoreConnectError(RuntimeError):
    pass


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _read_der_length(data: bytes, offset: int) -> tuple[int, int]:
    first = data[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    count = first & 0x7F
    if count == 0 or count > 4:
        raise AppStoreConnectError("Unsupported DER length")
    return int.from_bytes(data[offset : offset + count], "big"), offset + count


def der_signature_to_raw(signature: bytes, width: int = 32) -> bytes:
    """Convert OpenSSL's DER ECDSA signature into the JWT r||s encoding."""
    if not signature or signature[0] != 0x30:
        raise AppStoreConnectError("OpenSSL returned an invalid ECDSA signature")
    sequence_length, offset = _read_der_length(signature, 1)
    if offset + sequence_length != len(signature):
        raise AppStoreConnectError("Malformed DER ECDSA sequence")

    parts: list[bytes] = []
    for _ in range(2):
        if offset >= len(signature) or signature[offset] != 0x02:
            raise AppStoreConnectError("Malformed DER ECDSA integer")
        integer_length, offset = _read_der_length(signature, offset + 1)
        integer = signature[offset : offset + integer_length]
        offset += integer_length
        integer = integer.lstrip(b"\x00")
        if len(integer) > width:
            raise AppStoreConnectError("ECDSA integer is wider than P-256")
        parts.append(integer.rjust(width, b"\x00"))
    return b"".join(parts)


class ASCClient:
    def __init__(self, key_id: str, issuer_id: str | None, private_key: Path):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = private_key
        self._token: str | None = None
        self._token_expiry = 0

    @classmethod
    def from_environment(cls) -> "ASCClient":
        key_id = os.environ.get("ASC_KEY_ID")
        issuer_id = os.environ.get("ASC_ISSUER_ID") or None
        key_path = os.environ.get("ASC_PRIVATE_KEY_PATH")
        if not key_id or not key_path:
            raise AppStoreConnectError(
                "Set ASC_KEY_ID and ASC_PRIVATE_KEY_PATH. Set ASC_ISSUER_ID for a team key."
            )
        private_key = Path(key_path).expanduser()
        if not private_key.is_file():
            raise AppStoreConnectError(f"Private key not found: {private_key}")
        return cls(key_id, issuer_id, private_key)

    def token(self) -> str:
        now = int(time.time())
        if self._token and now < self._token_expiry - 30:
            return self._token

        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload: dict[str, Any] = {
            "aud": "appstoreconnect-v1",
            "iat": now,
            "exp": now + 15 * 60,
        }
        if self.issuer_id:
            payload["iss"] = self.issuer_id
        else:
            payload["sub"] = "user"

        signing_input = (
            b64url(json.dumps(header, separators=(",", ":")).encode())
            + "."
            + b64url(json.dumps(payload, separators=(",", ":")).encode())
        )
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(self.private_key)],
            input=signing_input.encode("ascii"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise AppStoreConnectError(
                "Unable to sign JWT: " + result.stderr.decode("utf-8", "replace").strip()
            )
        self._token = signing_input + "." + b64url(der_signature_to_raw(result.stdout))
        self._token_expiry = payload["exp"]
        return self._token

    def request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        if not path.startswith("/"):
            path = "/" + path
        url = API_BASE + path
        if query:
            url += "?" + urlencode(query, doseq=True)
        payload = None if body is None else json.dumps(body).encode("utf-8")
        request = Request(
            url,
            data=payload,
            method=method.upper(),
            headers={
                "Authorization": "Bearer " + self.token(),
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "kromatika-app-store-connect/1",
            },
        )
        try:
            with urlopen(request, timeout=45) as response:
                raw = response.read()
        except HTTPError as error:
            raw = error.read().decode("utf-8", "replace")
            raise AppStoreConnectError(f"Apple API {error.code} for {method} {path}: {raw}")
        except URLError as error:
            raise AppStoreConnectError(f"Apple API request failed: {error.reason}")
        return {} if not raw else json.loads(raw)


def relation(resource_type: str, resource_id: str) -> dict[str, Any]:
    return {"data": {"type": resource_type, "id": resource_id}}


def one(items: list[dict[str, Any]], description: str) -> dict[str, Any]:
    if len(items) != 1:
        raise AppStoreConnectError(f"Expected one {description}, found {len(items)}")
    return items[0]


def resolve_app(client: ASCClient, bundle_id: str) -> dict[str, Any]:
    result = client.request(
        "GET", "/v1/apps", query={"filter[bundleId]": bundle_id, "limit": 2}
    )
    return one(result.get("data", []), f"app with bundle ID {bundle_id}")


def get_versions(client: ASCClient, app_id: str) -> list[dict[str, Any]]:
    return client.request(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions",
        query={"filter[platform]": "IOS", "limit": 50},
    ).get("data", [])


def find_version(client: ASCClient, app_id: str, version: str) -> dict[str, Any]:
    matches = [
        item
        for item in get_versions(client, app_id)
        if item.get("attributes", {}).get("versionString") == version
    ]
    return one(matches, f"iOS App Store version {version}")


def find_build(client: ASCClient, app_id: str, build_number: str) -> dict[str, Any]:
    result = client.request(
        "GET",
        f"/v1/apps/{app_id}/builds",
        query={"filter[version]": build_number, "limit": 20},
    )
    return one(result.get("data", []), f"build {build_number}")


def print_json(value: Any) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def command_status(client: ASCClient, args: argparse.Namespace) -> None:
    app = resolve_app(client, args.bundle_id)
    app_id = app["id"]
    versions = get_versions(client, app_id)
    builds = client.request(
        "GET", f"/v1/apps/{app_id}/builds", query={"limit": 10, "sort": "-uploadedDate"}
    ).get("data", [])
    reviews = client.request(
        "GET", f"/v1/apps/{app_id}/reviewSubmissions", query={"limit": 10}
    ).get("data", [])
    print_json(
        {
            "app": {"id": app_id, **app.get("attributes", {})},
            "versions": [
                {"id": item["id"], **item.get("attributes", {})} for item in versions
            ],
            "builds": [
                {"id": item["id"], **item.get("attributes", {})} for item in builds
            ],
            "reviewSubmissions": [
                {"id": item["id"], **item.get("attributes", {})} for item in reviews
            ],
        }
    )


def command_attach_build(client: ASCClient, args: argparse.Namespace) -> None:
    app = resolve_app(client, args.bundle_id)
    version = find_version(client, app["id"], args.version)
    build = find_build(client, app["id"], args.build)
    path = f"/v1/appStoreVersions/{version['id']}/relationships/build"
    body = {"data": {"type": "builds", "id": build["id"]}}
    if not args.apply:
        print_json({"dryRun": True, "method": "PATCH", "path": path, "body": body})
        return
    client.request("PATCH", path, body=body)
    print(f"Attached build {args.build} to App Store version {args.version}.")


def _game_center_detail(client: ASCClient, app_id: str) -> dict[str, Any]:
    result = client.request("GET", f"/v1/apps/{app_id}/gameCenterDetail")
    data = result.get("data")
    if not data:
        raise AppStoreConnectError("Game Center is not enabled for this app")
    return data


def command_game_center(client: ASCClient, args: argparse.Namespace) -> None:
    app = resolve_app(client, args.bundle_id)
    detail = _game_center_detail(client, app["id"])
    leaderboards = client.request(
        "GET",
        f"/v1/gameCenterDetails/{detail['id']}/gameCenterLeaderboardsV2",
        query={"limit": 200},
    ).get("data", [])
    print_json(
        {
            "gameCenterDetailId": detail["id"],
            "leaderboards": [
                {"id": item["id"], **item.get("attributes", {})}
                for item in leaderboards
            ],
        }
    )


def command_ensure_streak(client: ASCClient, args: argparse.Namespace) -> None:
    app = resolve_app(client, args.bundle_id)
    detail = _game_center_detail(client, app["id"])
    existing = client.request(
        "GET",
        f"/v1/gameCenterDetails/{detail['id']}/gameCenterLeaderboardsV2",
        query={"limit": 200},
    ).get("data", [])
    match = next(
        (
            item
            for item in existing
            if item.get("attributes", {}).get("vendorIdentifier")
            == STREAK_LEADERBOARD_ID
        ),
        None,
    )
    if match:
        print(f"Leaderboard already exists: {match['id']} ({STREAK_LEADERBOARD_ID})")
        return

    path = "/v2/gameCenterLeaderboards"
    body = {
        "data": {
            "type": "gameCenterLeaderboards",
            "attributes": {
                "defaultFormatter": "INTEGER",
                "referenceName": "Longest Daily Streak",
                "scoreRangeStart": 1,
                "scoreRangeEnd": 36500,
                "scoreSortType": "DESC",
                "submissionType": "BEST_SCORE",
                "vendorIdentifier": STREAK_LEADERBOARD_ID,
                "visibility": "SHOW_FOR_ALL",
            },
            "relationships": {
                "gameCenterDetail": relation("gameCenterDetails", detail["id"])
            },
        }
    }
    if not args.apply:
        print_json({"dryRun": True, "method": "POST", "path": path, "body": body})
        return
    created = client.request("POST", path, body=body)["data"]
    print(
        "Created the leaderboard base resource. Add its English localization and "
        "include its version in the next review submission in App Store Connect."
    )
    print_json({"id": created["id"], **created.get("attributes", {})})


def _draft_review(client: ASCClient, app_id: str) -> dict[str, Any] | None:
    result = client.request(
        "GET",
        f"/v1/apps/{app_id}/reviewSubmissions",
        query={"filter[state]": "READY_FOR_REVIEW", "filter[platform]": "IOS", "limit": 20},
    )
    matches = result.get("data", [])
    if len(matches) > 1:
        raise AppStoreConnectError("More than one iOS draft review submission exists")
    return matches[0] if matches else None


def command_submit(client: ASCClient, args: argparse.Namespace) -> None:
    app = resolve_app(client, args.bundle_id)
    version = find_version(client, app["id"], args.version)
    draft = _draft_review(client, app["id"])

    planned: list[dict[str, Any]] = []
    if not draft:
        planned.append(
            {
                "method": "POST",
                "path": "/v1/reviewSubmissions",
                "body": {
                    "data": {
                        "type": "reviewSubmissions",
                        "attributes": {"platform": "IOS"},
                        "relationships": {"app": relation("apps", app["id"])},
                    }
                },
            }
        )
    planned.append(
        {
            "method": "POST",
            "path": "/v1/reviewSubmissionItems",
            "body": {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": relation(
                            "reviewSubmissions", draft["id"] if draft else "<new draft id>"
                        ),
                        "appStoreVersion": relation("appStoreVersions", version["id"]),
                    },
                }
            },
        }
    )
    planned.append(
        {
            "method": "PATCH",
            "path": "/v1/reviewSubmissions/<draft id>",
            "body": {
                "data": {
                    "type": "reviewSubmissions",
                    "id": "<draft id>",
                    "attributes": {"submitted": True},
                }
            },
        }
    )
    if not args.apply:
        print_json({"dryRun": True, "version": args.version, "requests": planned})
        return
    if not args.confirm_submit:
        raise AppStoreConnectError(
            "Refusing to send the version to App Review without --confirm-submit"
        )

    if not draft:
        draft = client.request("POST", planned[0]["path"], body=planned[0]["body"])["data"]
    item_body = planned[-2]["body"]
    item_body["data"]["relationships"]["reviewSubmission"] = relation(
        "reviewSubmissions", draft["id"]
    )
    client.request("POST", "/v1/reviewSubmissionItems", body=item_body)
    submit_body = {
        "data": {
            "type": "reviewSubmissions",
            "id": draft["id"],
            "attributes": {"submitted": True},
        }
    }
    client.request("PATCH", f"/v1/reviewSubmissions/{draft['id']}", body=submit_body)
    print(f"Submitted App Store version {args.version} for review.")


def command_upload(_: ASCClient, args: argparse.Namespace) -> None:
    ipa = Path(args.ipa).expanduser().resolve()
    if not ipa.is_file():
        raise AppStoreConnectError(f"IPA not found: {ipa}")
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        raise AppStoreConnectError("Upload requires ASC_KEY_ID and ASC_ISSUER_ID")
    action = "--validate-app" if args.validate_only else "--upload-app"
    command = [
        "xcrun",
        "altool",
        action,
        "-f",
        str(ipa),
        "-t",
        "ios",
        "--apiKey",
        key_id,
        "--apiIssuer",
        issuer_id,
        "--output-format",
        "json",
    ]
    if not args.apply:
        print_json({"dryRun": True, "command": command})
        return
    subprocess.run(command, check=True)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    commands = root.add_subparsers(dest="command", required=True)

    status = commands.add_parser("status", help="Show versions, builds, and review state")
    status.set_defaults(handler=command_status)

    game_center = commands.add_parser("game-center", help="List Game Center leaderboards")
    game_center.set_defaults(handler=command_game_center)

    streak = commands.add_parser(
        "ensure-streak-leaderboard", help="Create the Kromatika longest-streak board if absent"
    )
    streak.add_argument("--apply", action="store_true")
    streak.set_defaults(handler=command_ensure_streak)

    attach = commands.add_parser("attach-build", help="Attach an uploaded build to a version")
    attach.add_argument("--version", required=True)
    attach.add_argument("--build", required=True)
    attach.add_argument("--apply", action="store_true")
    attach.set_defaults(handler=command_attach_build)

    submit = commands.add_parser("submit", help="Add a version to a review and submit it")
    submit.add_argument("--version", required=True)
    submit.add_argument("--apply", action="store_true")
    submit.add_argument("--confirm-submit", action="store_true")
    submit.set_defaults(handler=command_submit)

    upload = commands.add_parser("upload", help="Validate or upload an IPA with altool")
    upload.add_argument("--ipa", required=True)
    upload.add_argument("--validate-only", action="store_true")
    upload.add_argument("--apply", action="store_true")
    upload.set_defaults(handler=command_upload)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        client = ASCClient.from_environment()
        args.handler(client, args)
        return 0
    except (AppStoreConnectError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
