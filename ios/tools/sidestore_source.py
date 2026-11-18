#!/usr/bin/env python3
"""Writes the SideStore / AltStore source for the iPhone app: source.json listing the repository's iPhone builds.

Each build the iPhone workflow publishes is a pre-release tagged ios-v<version> (0.1.<run>) with PokeDaisy-iOS.ipa attached;
the app inside carries that version (CFBundleShortVersionString) and the run number as its build (CFBundleVersion), which is
how SideStore tells an update from what's installed. The workflow then puts source.json on the `sidestore` branch, read
through raw.githubusercontent.com: the URL added to SideStore once, kept across builds.

  sidestore_source.py --repo OWNER/REPO --releases releases.json --out source.json

releases.json is the GitHub API's list of releases (gh api repos/OWNER/REPO/releases). Newest MAX_VERSIONS builds are listed.
"""
import argparse
import json
import re
import sys

TAG = re.compile(r"ios-v(\d+\.\d+\.(\d+))")
IPA = "PokeDaisy-iOS.ipa"
BUNDLE_ID = "com.pokedaisy.ios"
MIN_OS = "17.0"
MAX_VERSIONS = 10
BRANCH = "ios-duo"
ICON_PATH = "ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"


def versions(releases):
    out = []
    for r in releases:
        m = TAG.fullmatch(r.get("tag_name", ""))
        if not m or r.get("draft"):
            continue
        assets = [a for a in r.get("assets", []) if a.get("name") == IPA]
        if len(assets) != 1:
            continue
        a = assets[0]
        out.append({
            "version": m.group(1),
            "buildVersion": m.group(2),
            "date": r.get("published_at") or r.get("created_at"),
            "localizedDescription": (r.get("body") or r.get("name") or r["tag_name"]).strip(),
            "downloadURL": a["browser_download_url"],
            "size": a["size"],
            "minOSVersion": MIN_OS,
        })
    out.sort(key=lambda v: int(v["buildVersion"]), reverse=True)
    return out[:MAX_VERSIONS]


def source(repo, vs):
    owner, name = repo.split("/", 1)
    source_url = f"https://raw.githubusercontent.com/{repo}/sidestore/source.json"
    icon = f"https://raw.githubusercontent.com/{repo}/{BRANCH}/{ICON_PATH}"
    return {
        "name": "PokeDaisy for iPhone (unofficial port)",
        "identifier": f"io.github.{owner.lower()}.{name.lower()}",
        "sourceURL": source_url,
        "subtitle": "iPhone builds of PokeDaisy, laid out for the iPhone Duo",
        "description": (
            f"Unofficial iPhone builds of PokeDaisy from https://github.com/{repo} (branch {BRANCH}). "
            "PokeDaisy is by lidor30 (https://github.com/lidor30/pokedaisy); this port isn't the official app, "
            "so report problems with it to the fork. No games are included: play your own."
        ),
        "website": f"https://github.com/{repo}/tree/{BRANCH}/ios",
        "iconURL": icon,
        "tintColor": "3C94FA",
        "apps": [{
            "name": "PokeDaisy",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": f"{owner} (port of PokeDaisy by lidor30)",
            "subtitle": "Your Pokemon game and a live companion, side by side",
            "localizedDescription": (
                "Plays your own GBA, Game Boy and Game Boy Color games with PokeDaisy's live companion beside the game: "
                "party, bag, map, guide, Pokedex, battle info and more. Laid out for the iPhone Duo (game and companion "
                "on screen together, folded or open) and works on other iPhones. Early preview. "
                f"Source and notes: https://github.com/{repo}/tree/{BRANCH}/ios"
            ),
            "iconURL": icon,
            "tintColor": "3C94FA",
            "category": "games",
            "screenshots": [],
            "versions": vs,
            "appPermissions": {"entitlements": [], "privacy": {}},
        }],
        "news": [],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repo", required=True)
    p.add_argument("--releases", required=True)
    p.add_argument("--out", required=True)
    args = p.parse_args()
    with open(args.releases) as f:
        releases = json.load(f)
    vs = versions(releases)
    if not vs:
        sys.exit("no iPhone build (ios-v* release with %s) to list" % IPA)
    with open(args.out, "w") as f:
        json.dump(source(args.repo, vs), f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"source.json: {len(vs)} build(s), newest {vs[0]['version']} ({vs[0]['buildVersion']})")


if __name__ == "__main__":
    main()
