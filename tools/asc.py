#!/usr/bin/env python3
"""A small App Store Connect API client — the stock python3 of a Mac, no third-party modules.

    tools/asc.py builds                  recent uploads: version, build, platform, processing state
    tools/asc.py bundle-id [--create]    look up (or register) the app's bundle ID
    tools/asc.py whats-new <build> <file>   the "What to Test" notes testers see for that build (all
                                         its platforms), from a text file
    tools/asc.py pricing [--set]         price and countries: free, every territory, and new ones
                                         as Apple adds them; --set creates whichever is missing
    tools/asc.py listing [--apply]       the App Store listing from docs/app-store/listing.json, on both
                                         platforms: version, build, text, URLs, category, age rating
                                         (all "none"), Game Center on, screenshots from
                                         build/store-shots; without --apply it only lists differences
    tools/asc.py submit [--submit]       one App Review submission per platform with its version; the
                                         first also carries every Game Center leaderboard and set
                                         not yet live (Apple wants them with the first version).
                                         Without --submit it only fills the drafts and lists them
    tools/asc.py gamecenter [--create]   Game Center and iCloud for the app: the bundle ID's
                                         capabilities, the four leaderboards and their set (spec
                                         "Scores"); --create adds whatever is missing, and only that

Credentials come from the api.env that `make` reads (ASC_ENV, default
$HOME/.config/appstoreconnect/api.env): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. The ES256 token is
signed with openssl, so the key never leaves the file.
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = "com.oneoffendeavors.solitaire"
ENV_FILE = os.environ.get("ASC_ENV") or os.path.join(os.environ["HOME"], ".config/appstoreconnect/api.env")


def load_env():
    try:
        with open(ENV_FILE) as f:
            return dict(line.strip().split("=", 1) for line in f if "=" in line and not line.startswith("#"))
    except OSError:
        sys.exit(f"no App Store Connect settings at {ENV_FILE} (see README › Signing)")


ENV = load_env()


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_raw(der):
    """openssl's ECDSA signature (DER SEQUENCE of r, s) -> the 64-byte r||s a JWT carries."""
    i = 2 if der[1] < 0x80 else 3
    out = b""
    for _ in range(2):
        assert der[i] == 0x02, "unexpected signature encoding"
        n = der[i + 1]
        out += der[i + 2:i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + n
    return out


def token():
    now = int(time.time())
    head = b64(json.dumps({"alg": "ES256", "kid": ENV["ASC_KEY_ID"], "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": ENV["ASC_ISSUER_ID"], "iat": now, "exp": now + 600,
                           "aud": "appstoreconnect-v1"}).encode())
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", ENV["ASC_KEY_PATH"]],
                         input=head + b"." + body, capture_output=True, check=True).stdout
    return (head + b"." + body + b"." + b64(der_to_raw(sig))).decode()


def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(),
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, json.loads(body) if body else {}       # 204 No Content: no body
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def get(path):
    status, data = call("GET", path)
    if status != 200:
        sys.exit(f"App Store Connect said {status}: {json.dumps(data.get('errors', data))[:400]}")
    return data


def builds():
    apps = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    if not apps:
        sys.exit(f"no App Store Connect app with bundle ID {BUNDLE_ID} — create the app record first")
    app = apps[0]
    print(f"{app['attributes']['name']} ({BUNDLE_ID})")
    data = get(f"/v1/builds?filter[app]={app['id']}&sort=-uploadedDate&limit=10&include=preReleaseVersion")
    versions = {v["id"]: v["attributes"] for v in data.get("included", []) if v["type"] == "preReleaseVersions"}
    if not data["data"]:
        print("  no builds yet (a fresh upload takes a few minutes to appear)")
    for b in data["data"]:
        a = b["attributes"]
        pre = versions.get(b["relationships"]["preReleaseVersion"]["data"]["id"], {})
        print(f"  {pre.get('platform', '?'):6} {pre.get('version', '?'):5} build {a['version']:>12}  "
              f"{a['processingState']:10}  uploaded {a['uploadedDate'][:16].replace('T', ' ')}"
              + ("  EXPIRED" if a.get("expired") else ""))


def bundle_id(create):
    data = get("/v1/bundleIds?filter[identifier]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    for d in data:
        print(f"{d['attributes']['identifier']}  {d['attributes']['platform']}  team {d['attributes']['seedId']}")
    if not data and create:
        status, d = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": BUNDLE_ID, "name": "Solitaire", "platform": "UNIVERSAL"}}})
        if status != 201:
            sys.exit(f"could not register {BUNDLE_ID}: {status} {json.dumps(d.get('errors', d))[:400]}")
        print(f"registered {BUNDLE_ID} (UNIVERSAL)")
    elif not data:
        print(f"{BUNDLE_ID} is not registered (pass --create)")


# Spec "Scores": one board per draw mode and difficulty, each player's best kept, highest first.
LEADERBOARDS = [
    ("com.oneoffendeavors.solitaire.draw1", "Draw 1"),
    ("com.oneoffendeavors.solitaire.draw3", "Draw 3"),
    ("com.oneoffendeavors.solitaire.draw1.hardcore", "Draw 1 · Hard Core"),
    ("com.oneoffendeavors.solitaire.draw3.hardcore", "Draw 3 · Hard Core"),
]
LEADERBOARD_SET = ("com.oneoffendeavors.solitaire.leaderboards", "Solitaire")
CAPABILITIES = {
    "GAME_CENTER": None,
    "ICLOUD": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}],
}


def post(path, body, what):
    status, data = call("POST", path, body)
    if status not in (200, 201, 204):
        sys.exit(f"could not {what}: {status} {json.dumps(data.get('errors', data) if data else '')[:500]}")
    print(f"  created: {what}")
    return data


def rel(kind, ident):
    return {"data": {"type": kind, "id": ident}}


def gamecenter(create):
    """Reports, and with create adds, what Game Center and iCloud need. Never changes or removes
    anything that exists."""
    apps = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    if not apps:
        sys.exit(f"no App Store Connect app with bundle ID {BUNDLE_ID}")
    app = apps[0]["id"]
    bundle = get("/v1/bundleIds?filter[identifier]=" + urllib.parse.quote(BUNDLE_ID))["data"][0]["id"]

    have = {c["attributes"]["capabilityType"]
            for c in get(f"/v1/bundleIds/{bundle}/bundleIdCapabilities")["data"]}
    for cap, settings in CAPABILITIES.items():
        print(f"capability {cap}: {'on' if cap in have else 'missing'}")
        if cap not in have and create:
            attributes = {"capabilityType": cap}
            if settings:
                attributes["settings"] = settings
            post("/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": attributes,
                 "relationships": {"bundleId": rel("bundleIds", bundle)}}}, f"capability {cap}")

    status, detail = call("GET", f"/v1/apps/{app}/gameCenterDetail")
    detail_id = detail["data"]["id"] if status == 200 and detail.get("data") else None
    print(f"Game Center for the app: {'on' if detail_id else 'missing'}")
    if not detail_id:
        if not create:
            return
        detail_id = post("/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails",
                         "relationships": {"app": rel("apps", app)}}}, "Game Center detail")["data"]["id"]

    boards = {b["attributes"]["vendorIdentifier"]: b["id"]
              for b in get(f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboards?limit=50")["data"]}
    for vendor, name in LEADERBOARDS:
        print(f"leaderboard {vendor}: {'present' if vendor in boards else 'missing'}")
        if vendor in boards or not create:
            continue
        board = post("/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards", "attributes": {
            "referenceName": f"Solitaire — {name}", "vendorIdentifier": vendor, "defaultFormatter": "INTEGER",
            "submissionType": "BEST_SCORE", "scoreSortType": "DESC", "scoreRangeStart": "0",
            "scoreRangeEnd": "1000"}, "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}},
            f"leaderboard {name}")["data"]["id"]
        boards[vendor] = board
        post("/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations",
             "attributes": {"locale": "en-US", "name": name, "formatterSuffix": " points",
                            "formatterSuffixSingular": " point"},
             "relationships": {"gameCenterLeaderboard": rel("gameCenterLeaderboards", board)}}},
             f"English name for {name}")

    sets = {s["attributes"]["vendorIdentifier"]: s["id"]
            for s in get(f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboardSets?limit=50")["data"]}
    vendor, name = LEADERBOARD_SET
    print(f"leaderboard set {vendor}: {'present' if vendor in sets else 'missing'}")
    if vendor not in sets and create:
        sets[vendor] = post("/v1/gameCenterLeaderboardSets", {"data": {"type": "gameCenterLeaderboardSets",
            "attributes": {"referenceName": f"{name} leaderboards", "vendorIdentifier": vendor},
            "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}}, "leaderboard set")["data"]["id"]
        post("/v1/gameCenterLeaderboardSetLocalizations", {"data": {"type": "gameCenterLeaderboardSetLocalizations",
             "attributes": {"locale": "en-US", "name": name},
             "relationships": {"gameCenterLeaderboardSet": rel("gameCenterLeaderboardSets", sets[vendor])}}},
             "English name for the set")
    if vendor in sets:
        members = {m["id"] for m in get(f"/v1/gameCenterLeaderboardSets/{sets[vendor]}/relationships/gameCenterLeaderboards?limit=50")["data"]}
        missing = [boards[v] for v, _ in LEADERBOARDS if v in boards and boards[v] not in members]
        print(f"  set members: {len(members)} of {len(LEADERBOARDS)}")
        if missing and create:
            post(f"/v1/gameCenterLeaderboardSets/{sets[vendor]}/relationships/gameCenterLeaderboards",
                 {"data": [{"type": "gameCenterLeaderboards", "id": b} for b in missing]},
                 f"{len(missing)} leaderboards added to the set")


def app_id():
    apps = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    if not apps:
        sys.exit(f"no App Store Connect app with bundle ID {BUNDLE_ID}")
    return apps[0]["id"]


def pricing(apply):
    """Free, in every territory (the 1.1 decision). Neither can be changed back to "unset", only
    to another price or list, so --set only ever creates what is missing."""
    app = app_id()
    status, prices = call("GET", f"/v1/appPriceSchedules/{app}/manualPrices?include=appPricePoint")
    points = [i["attributes"].get("customerPrice") for i in prices.get("included", [])] if status == 200 else []
    print(f"  price: {'free' if points == ['0.0'] else (points or 'not set')}")
    if not points and apply:
        free = [p for p in get(f"/v1/apps/{app}/appPricePoints?filter[territory]=USA&limit=5")["data"]
                if p["attributes"]["customerPrice"] in ("0", "0.0", "0.00")]
        if len(free) != 1:
            sys.exit("could not find the free price point")
        post("/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": rel("apps", app), "baseTerritory": rel("territories", "USA"),
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": rel("appPricePoints", free[0]["id"])}}]},
            "price schedule: free (base territory USA)")
    status, avail = call("GET", f"/v1/apps/{app}/appAvailabilityV2")
    if status == 200:
        a = avail["data"]["attributes"]
        print(f"  availability: set (new territories automatically: {a.get('availableInNewTerritories')})")
    else:
        print("  availability: not set")
        if apply:
            territories = [t["id"] for t in get("/v1/territories?limit=200")["data"]]
            post("/v2/appAvailabilities", {
                "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                         "relationships": {"app": rel("apps", app), "territoryAvailabilities": {
                             "data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
                "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                              "relationships": {"territory": rel("territories", t)}} for t in territories]},
                f"availability: all {len(territories)} territories, and new ones")


LISTING = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "app-store", "listing.json")
SHOTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "store-shots")
AGE_NONE = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
            "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation",
            "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
            "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
AGE_NO = ["advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
          "parentalControls", "unrestrictedWebAccess", "userGeneratedContent", "socialMedia"]


def patch(path, kind, ident, attributes=None, relationships=None, what=""):
    data = {"type": kind, "id": ident}
    if attributes:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    status, d = call("PATCH", path, {"data": data})
    if status not in (200, 204):
        sys.exit(f"could not update {what}: {status} {json.dumps(d.get('errors', d) if d else '')[:600]}")
    print(f"  updated: {what}")


def differs(label, current, wanted, apply, action):
    """Prints a difference; applies it with --apply. Returns whether there was one."""
    if current == wanted:
        return False
    show = lambda v: (repr(v)[:70] + "…") if len(repr(v)) > 72 else repr(v)
    print(f"  {label}: {show(current)} → {show(wanted)}")
    if apply:
        action()
    return True


def listing(apply):
    want = json.load(open(LISTING))
    description = "\n".join(want["description"])
    app = app_id()
    changes = 0

    # The app itself: whether it uses third-party content (the user's declaration: it doesn't).
    rights = get(f"/v1/apps/{app}")["data"]["attributes"].get("contentRightsDeclaration")
    changes += differs("content rights", rights, want["contentRightsDeclaration"], apply,
                       lambda: patch(f"/v1/apps/{app}", "apps", app, {"contentRightsDeclaration":
                                                                      want["contentRightsDeclaration"]},
                                     what="content rights declaration"))

    # The app's own info (both platforms): subtitle, privacy URL, subcategory, age rating.
    info = [i for i in get(f"/v1/apps/{app}/appInfos")["data"]
            if i["attributes"].get("appStoreState") != "READY_FOR_SALE"][0]
    loc = get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"][0]
    for key in ("subtitle", "privacyPolicyUrl"):
        changes += differs(f"app info {key}", loc["attributes"].get(key), want[key], apply,
                           lambda key=key: patch(f"/v1/appInfoLocalizations/{loc['id']}", "appInfoLocalizations",
                                                 loc["id"], {key: want[key]}, what=f"app info {key}"))
    sub = (get(f"/v1/appInfos/{info['id']}/primarySubcategoryOne").get("data") or {}).get("id")
    changes += differs("subcategory", sub, want["primarySubcategory"], apply,
                       lambda: patch(f"/v1/appInfos/{info['id']}", "appInfos", info["id"], relationships={
                           "primarySubcategoryOne": rel("appCategories", want["primarySubcategory"])},
                           what="subcategory"))
    age = get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    wanted_age = {**{k: "NONE" for k in AGE_NONE}, **{k: False for k in AGE_NO}}
    current_age = {k: age["attributes"].get(k) for k in wanted_age}
    changes += differs("age rating answers", sum(v is not None for v in current_age.values()) if current_age != wanted_age else "all none",
                       "all none", apply,
                       lambda: patch(f"/v1/ageRatingDeclarations/{age['id']}", "ageRatingDeclarations", age["id"],
                                     wanted_age, what="age rating: every answer none / no"))

    builds = {b["relationships"]["preReleaseVersion"]["data"]["id"]: b for b in
              get(f"/v1/builds?filter[app]={app}&filter[version]={want['build']}&include=preReleaseVersion")["data"]}
    platform_of_pre = {}
    for b in get(f"/v1/builds?filter[app]={app}&filter[version]={want['build']}&include=preReleaseVersion").get("included", []):
        platform_of_pre[b["id"]] = b["attributes"]["platform"]
    build_for = {platform_of_pre[pre]: b["id"] for pre, b in builds.items()}

    for v in get(f"/v1/apps/{app}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED")["data"]:
        platform, vid, a = v["attributes"]["platform"], v["id"], v["attributes"]
        print(f"{platform}:")
        for key, value in (("versionString", want["version"]), ("copyright", want["copyright"]),
                           ("releaseType", "AFTER_APPROVAL")):
            changes += differs(key, a.get(key), value, apply,
                               lambda key=key, value=value: patch(f"/v1/appStoreVersions/{vid}", "appStoreVersions",
                                                                  vid, {key: value}, what=key))
        current_build = (get(f"/v1/appStoreVersions/{vid}/build").get("data") or {}).get("id")
        if platform not in build_for:
            sys.exit(f"build {want['build']} has no {platform} upload")
        changes += differs("build", current_build, build_for[platform], apply,
                           lambda: patch(f"/v1/appStoreVersions/{vid}", "appStoreVersions", vid, relationships={
                               "build": rel("builds", build_for[platform])}, what=f"build {want['build']}"))
        vloc = [l for l in get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
                if l["attributes"]["locale"] == "en-US"][0]
        for key, value in (("description", description), ("keywords", want["keywords"]),
                           ("promotionalText", want["promotionalText"]), ("supportUrl", want["supportUrl"]),
                           ("marketingUrl", want["marketingUrl"])):
            changes += differs(key, vloc["attributes"].get(key), value, apply,
                               lambda key=key, value=value: patch(f"/v1/appStoreVersionLocalizations/{vloc['id']}",
                                                                  "appStoreVersionLocalizations", vloc["id"],
                                                                  {key: value}, what=key))
        gc = get(f"/v1/appStoreVersions/{vid}/gameCenterAppVersion").get("data")
        changes += differs("Game Center", bool(gc and gc["attributes"].get("enabled")), True, apply,
                           lambda: post("/v1/gameCenterAppVersions", {"data": {
                               "type": "gameCenterAppVersions",
                               "relationships": {"appStoreVersion": rel("appStoreVersions", vid)}}},
                               "Game Center for this version"))
        for display, files in want["screenshots"][platform].items():
            changes += screenshots(vloc["id"], display, files, apply)
    print(("applied" if apply else "differences") + f": {changes}" if changes else "the listing matches")


def screenshots(loc_id, display, files, apply):
    """One screenshot set: exactly `files`, in order. A set that differs is emptied and refilled."""
    sets = {s["attributes"]["screenshotDisplayType"]: s for s in
            get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]}
    current = []
    if display in sets:
        current = [s["attributes"]["fileName"] for s in
                   get(f"/v1/appScreenshotSets/{sets[display]['id']}/appScreenshots")["data"]]
    if current == files:
        return 0
    print(f"  screenshots {display}: {len(current)} → {len(files)} ({', '.join(files)})")
    if not apply:
        return 1
    for name in files:
        if not os.path.exists(os.path.join(SHOTS, name)):
            sys.exit(f"missing {os.path.join(SHOTS, name)}")
    if display in sets:
        set_id = sets[display]["id"]
        for s in get(f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]:
            status, d = call("DELETE", f"/v1/appScreenshots/{s['id']}")
            if status not in (200, 204):
                sys.exit(f"could not remove an old screenshot: {status}")
    else:
        set_id = post("/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
            "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", loc_id)}}},
            f"screenshot set {display}")["data"]["id"]
    ids = []
    for name in files:
        data = open(os.path.join(SHOTS, name), "rb").read()
        shot = post("/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": rel("appScreenshotSets", set_id)}}}, f"screenshot {name}")["data"]
        for op in shot["attributes"]["uploadOperations"]:
            part = data[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                         headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
            with urllib.request.urlopen(req, timeout=120) as r:
                if r.status not in (200, 201, 204):
                    sys.exit(f"upload of {name} failed: {r.status}")
        patch(f"/v1/appScreenshots/{shot['id']}", "appScreenshots", shot["id"],
              {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}, what=f"uploaded {name}")
        ids.append(shot["id"])
    status, d = call("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
                     {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
    if status not in (200, 204):
        sys.exit(f"could not order {display}: {status} {json.dumps(d.get('errors', d) if d else '')[:300]}")
    return 1


def submit(really):
    app = app_id()
    # READY_FOR_REVIEW: a version already in a draft submission (adding it there moves it on).
    versions = get(f"/v1/apps/{app}/appStoreVersions?filter[appStoreState]="
                   "PREPARE_FOR_SUBMISSION,READY_FOR_REVIEW,DEVELOPER_REJECTED,REJECTED")["data"]
    if not versions:
        sys.exit("no version waiting to be submitted")
    gcd = get(f"/v1/apps/{app}/gameCenterDetail")["data"]["id"]
    components = []
    for kind, path, rel_name in (("gameCenterLeaderboardVersions", "gameCenterLeaderboardsV2", "gameCenterLeaderboardVersion"),
                                 ("gameCenterLeaderboardSetVersions", "gameCenterLeaderboardSetsV2", "gameCenterLeaderboardSetVersion")):
        d = get(f"/v1/gameCenterDetails/{gcd}/{path}?limit=50&include=versions")
        names = {}
        for item in d["data"]:
            for v in item["relationships"]["versions"]["data"]:
                names[v["id"]] = item["attributes"]["vendorIdentifier"]
        for inc in d.get("included", []):
            if inc["type"] == kind and inc["attributes"]["state"] == "PREPARE_FOR_SUBMISSION":
                components.append((rel_name, kind, inc["id"], names.get(inc["id"], "?")))
    drafts = {s["attributes"]["platform"]: s for s in
              get(f"/v1/reviewSubmissions?filter[app]={app}&filter[state]=READY_FOR_REVIEW")["data"]}
    for i, v in enumerate(sorted(versions, key=lambda v: v["attributes"]["platform"] != "IOS")):
        platform = v["attributes"]["platform"]
        sub = drafts.get(platform) or post("/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": platform},
            "relationships": {"app": rel("apps", app)}}}, f"{platform} draft submission")["data"]
        have = get(f"/v1/reviewSubmissions/{sub['id']}/items?limit=50&include=appStoreVersion,gameCenterLeaderboardVersion,gameCenterLeaderboardSetVersion")["data"]
        held = {r["data"]["id"] for item in have for r in item.get("relationships", {}).values()
                if isinstance(r, dict) and isinstance(r.get("data"), dict)}
        wanted = [("appStoreVersion", "appStoreVersions", v["id"], f"{platform} {v['attributes']['versionString']}")]
        if i == 0:
            wanted += components                                      # with the first platform's version only
        for rel_name, kind, ident, label in wanted:
            if ident not in held:
                post("/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                    "reviewSubmission": rel("reviewSubmissions", sub["id"]), rel_name: rel(kind, ident)}}},
                    f"{platform} item: {label}")
        print(f"{platform} submission {sub['id']}:")
        for _, _, _, label in wanted:
            print(f"  · {label}")
        if really:
            patch(f"/v1/reviewSubmissions/{sub['id']}", "reviewSubmissions", sub["id"], {"submitted": True},
                  what=f"{platform}: SUBMITTED for review")
    if not really:
        print("drafts only — run with --submit to send them to App Review")


def whats_new(build_number, path):
    """Sets the English "What to Test" text on every platform's upload of a build."""
    text = open(path).read().strip()
    if not text or len(text) > 4000:
        sys.exit(f"the notes must be 1-4000 characters (they are {len(text)})")
    app = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"][0]["id"]
    builds = get(f"/v1/builds?filter[app]={app}&filter[version]={urllib.parse.quote(build_number)}&limit=10")["data"]
    if not builds:
        sys.exit(f"no build {build_number} yet (an upload takes a few minutes to appear)")
    for b in builds:
        locs = get(f"/v1/builds/{b['id']}/betaBuildLocalizations")["data"]
        mine = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        if mine:
            status, data = call("PATCH", f"/v1/betaBuildLocalizations/{mine['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": mine["id"], "attributes": {"whatsNew": text}}})
        else:
            status, data = call("POST", "/v1/betaBuildLocalizations", {"data": {
                "type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
                "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
        if status not in (200, 201):
            sys.exit(f"could not set the notes on build {b['id']}: {status} {json.dumps(data.get('errors', data))[:400]}")
        print(f"  notes set on {build_number} ({b['id']})")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "builds"
    if cmd == "builds":
        builds()
    elif cmd == "bundle-id":
        bundle_id("--create" in sys.argv)
    elif cmd == "whats-new" and len(sys.argv) == 4:
        whats_new(sys.argv[2], sys.argv[3])
    elif cmd == "submit":
        submit("--submit" in sys.argv)
    elif cmd == "listing":
        listing("--apply" in sys.argv)
    elif cmd == "pricing":
        pricing("--set" in sys.argv)
    elif cmd == "gamecenter":
        gamecenter("--create" in sys.argv)
    else:
        sys.exit(__doc__)
