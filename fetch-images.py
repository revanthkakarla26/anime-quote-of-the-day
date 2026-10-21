#!/usr/bin/env python3
"""Download character pictures for quotes.json from AniList.

Looks up every character that has no picture in images/ yet, checks the match
appears in the right anime, saves the portrait as images/<slug>.<ext> and
records the AniList id and file name back in quotes.json. A pinned "anilist"
id skips the search, and a "search" name overrides the display name.

    python3 -I fetch-images.py            # fetch missing pictures
    python3 -I fetch-images.py --force    # re-fetch all of them

The pictures belong to their studios; they're cached here for personal use.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
QUOTES = os.path.join(HERE, "quotes.json")
IMAGES = os.path.join(HERE, "images")
API = "https://graphql.anilist.co"
UA = "reva.animequote/1.0 (Omarchy shell plugin)"

FIELDS = "id name{full} image{large} media(sort:POPULARITY_DESC,perPage:50){nodes{title{romaji english}}}"
BY_SEARCH = "query($s:String){Page(perPage:10){characters(search:$s){%s}}}" % FIELDS
BY_ID = "query($id:Int){Character(id:$id){%s}}" % FIELDS

# AniList allows 30 requests a minute while it runs degraded; stay under it.
REQUEST_GAP = 2.2


def norm(text):
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def in_anime(character, anime):
    want = norm(anime)
    for media in character["media"]["nodes"]:
        for title in (media["title"]["romaji"], media["title"]["english"]):
            title = norm(title)
            if title and (want in title or title in want):
                return True
    return False


def fetch(req, timeout):
    """Read a response, waiting out rate limits and retrying dropped connections."""
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read(2_000_000 + 1)
        except urllib.error.HTTPError as err:
            if err.code != 429 or attempt == 4:
                raise
            wait = int(err.headers.get("Retry-After") or 60)
            print(f"  rate limited, waiting {wait}s", flush=True)
            time.sleep(wait + 1)
        except (urllib.error.URLError, ConnectionError, TimeoutError) as err:
            if attempt == 4:
                raise
            wait = 5 * (attempt + 1)
            print(f"  {err}; retrying in {wait}s", flush=True)
            time.sleep(wait)


def post(query, variables):
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(API, data=body, headers={
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": UA,
    })
    return json.loads(fetch(req, 20))["data"]


def image_ext(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def download(url):
    data = fetch(urllib.request.Request(url, headers={"User-Agent": UA}), 30)
    if len(data) > 2_000_000:
        raise ValueError("picture is over 2 MB")
    ext = image_ext(data)
    if not ext:
        raise ValueError("not a PNG, JPEG or WebP picture")
    return data, ext


def find(slug, info):
    if info.get("anilist"):
        return post(BY_ID, {"id": int(info["anilist"])})["Character"]
    found = post(BY_SEARCH, {"s": info.get("search") or info["name"]})["Page"]["characters"]
    for character in found:
        if in_anime(character, info["anime"]):
            return character
    names = ", ".join(c["name"]["full"] for c in found) or "nothing"
    raise LookupError(f"no match in {info['anime']} (found {names})")


def save(data):
    # Keep the hand-written layout: one character or quote per line.
    def obj(d):
        return "{ " + ", ".join(f"{json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}" for k, v in d.items()) + " }"

    chars = ",\n".join(f"    {json.dumps(k)}: {obj(v)}" for k, v in data["characters"].items())
    quotes = ",\n".join(f"    {obj(q)}" for q in data["quotes"])
    text = '{\n  "characters": {\n' + chars + '\n  },\n  "quotes": [\n' + quotes + "\n  ]\n}\n"
    tmp = QUOTES + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, QUOTES)


def main():
    force = "--force" in sys.argv[1:]
    with open(QUOTES, encoding="utf-8") as f:
        data = json.load(f)
    os.makedirs(IMAGES, exist_ok=True)

    failed = []
    for slug, info in data["characters"].items():
        current = info.get("image")
        if current and os.path.exists(os.path.join(IMAGES, current)) and not force:
            continue
        try:
            character = find(slug, info)
            picture, ext = download(character["image"]["large"])
        except Exception as err:  # keep going; report at the end
            print(f"✗ {slug}: {err}", flush=True)
            failed.append(slug)
            time.sleep(REQUEST_GAP)
            continue

        name = f"{slug}.{ext}"
        for old in os.listdir(IMAGES):
            if old.rsplit(".", 1)[0] == slug and old != name:
                os.remove(os.path.join(IMAGES, old))
        with open(os.path.join(IMAGES, name), "wb") as f:
            f.write(picture)
        info["anilist"] = character["id"]
        info["image"] = name
        save(data)
        print(f"✓ {slug}: {character['name']['full']} (#{character['id']}, {len(picture) // 1024} KB)", flush=True)
        time.sleep(REQUEST_GAP)

    if failed:
        print(f"\n{len(failed)} without a picture: {', '.join(failed)}")
        print('Pin the right id with "anilist": <id> or set "search", then run again.')
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
