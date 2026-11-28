#!/usr/bin/env python3
"""Upload a release zip to the PoleSim Gear project on CurseForge.

Usage: tools/publish_curseforge.py <zip> <version> [release|beta|alpha] [--dry-run]

Environment:
  CF_API_TOKEN      CurseForge upload API token (authors.curseforge.com > API tokens). Repo secret.
  CF_PROJECT_ID     numeric project id (the project's overview page). Repo variable.
  CF_GAME_VERSIONS  optional, comma-separated game version names, e.g. "1.60.1".
                    Default: the TOC's "## Interface" (16001 -> 1.60.1).
  CF_VERSION_TYPE   optional, the game version type to match names in (default "Forever"): the same
                    version name can exist under several flavours.

The changelog is the version's notes from tools/release-notes.sh (the "**X over Y:**" paragraph of
docs/CHECKLIST.md), sent as Markdown. Polestar is declared as a required dependency.
--dry-run resolves the game version ids and prints the metadata without uploading.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from typing import NoReturn

API = "https://wow.curseforge.com/api"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "PoleSimGear", "PoleSimGear.toc")
RELATIONS = {"projects": [{"slug": "polestar", "type": "requiredDependency"}]}


def die(msg) -> NoReturn:
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def request(method, path, token, body=None, content_type=None):
    req = urllib.request.Request(API + path, data=body, method=method)
    req.add_header("X-Api-Token", token)
    req.add_header("User-Agent", "polesim-gear-publisher")
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        die("%s %s -> HTTP %d: %s" % (method, path, e.code, e.read().decode(errors="replace")[:500]))


def interface_versions():
    toc = open(TOC, encoding="utf-8").read()
    m = re.search(r"^## Interface:\s*(.+)$", toc, re.M) or die("no ## Interface in the TOC")
    names = []
    for part in m.group(1).split(","):
        n = int(part.strip())
        names.append("%d.%d.%d" % (n // 10000, (n // 100) % 100, n % 100))
    return names


def game_version_ids(token, wanted, type_name):
    types = request("GET", "/game/version-types", token)
    type_ids = {t["id"] for t in types if type_name.lower() in (t.get("name") or "").lower()}
    if not type_ids:
        die("CurseForge has no game version type named like %r; set CF_VERSION_TYPE" % type_name)
    versions = request("GET", "/game/versions", token)
    ids = []
    for name in wanted:
        match = [v["id"] for v in versions if v.get("name") == name and v.get("gameVersionTypeID") in type_ids]
        if not match:
            die("no %s game version named %s on CurseForge; set CF_GAME_VERSIONS" % (type_name, name))
        print("game version %s %s -> id %d" % (type_name, name, match[0]))
        ids.append(match[0])
    return ids


def changelog(version):
    out = subprocess.run([os.path.join(ROOT, "tools", "release-notes.sh"), version],
                         check=True, capture_output=True, text=True).stdout
    return out.strip()


def multipart(fields, file_field, file_path):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n'
                      % (boundary, name, value)).encode())
    with open(file_path, "rb") as f:
        data = f.read()
    parts.append(('--%s\r\nContent-Disposition: form-data; name="%s"; filename="%s"\r\n'
                  'Content-Type: application/zip\r\n\r\n' % (boundary, file_field, os.path.basename(file_path))).encode()
                 + data + b"\r\n")
    parts.append(("--%s--\r\n" % boundary).encode())
    return b"".join(parts), "multipart/form-data; boundary=" + boundary


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    if len(args) < 2:
        die(__doc__)
    zip_path, version = args[0], args[1]
    release_type = args[2] if len(args) > 2 else "release"
    if release_type not in ("release", "beta", "alpha"):
        die("release type must be release, beta or alpha")
    os.path.isfile(zip_path) or die("no file " + zip_path)
    token = os.environ.get("CF_API_TOKEN") or die("CF_API_TOKEN is not set")
    project = os.environ.get("CF_PROJECT_ID") or die("CF_PROJECT_ID is not set")

    wanted = [v.strip() for v in os.environ.get("CF_GAME_VERSIONS", "").split(",") if v.strip()] or interface_versions()
    ids = game_version_ids(token, wanted, os.environ.get("CF_VERSION_TYPE") or "Forever")
    metadata = {
        "changelog": changelog(version),
        "changelogType": "markdown",
        "displayName": "PoleSim Gear %s" % version,
        "gameVersions": ids,
        "releaseType": release_type,
        "relations": RELATIONS,
    }
    if dry:
        print(json.dumps(metadata, indent=2))
        return
    body, ctype = multipart({"metadata": json.dumps(metadata)}, "file", zip_path)
    result = request("POST", "/projects/%s/upload-file" % project, token, body, ctype)
    print("uploaded %s to CurseForge project %s as file id %s" % (zip_path, project, result.get("id")))


if __name__ == "__main__":
    main()
