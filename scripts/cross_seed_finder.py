#!/usr/bin/env python3
"""
Advanced Multi-Threaded Prowlarr Cross-Seed Opportunity Finder.

Features:
- Audit Mode (--audit): Detailed diagnostic auditing of skipped releases, secondary indexer misses, resolution mismatches, and size difference rejections.
- Direct C411 Native API Mode (--direct-c411): Bypasses Prowlarr's 100-release Cardigann cap by querying https://c411.org/api directly via `kubectl exec curl` inside K8s VPN pod.
- Sequential Page-by-Page Pipeline: Fetches 1 page (100 releases), filters candidates, evaluates matches across secondary trackers, and gently proceeds to the next page.
- Fuzzy Title Matching & Episode Check: Eliminates cross-show false positives.
- Dynamic Human-Readable Sizes: Displays sizes in MB / GB.
- Structured JSON Export: Export results via -o / --output-json.
"""

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor, as_completed
import difflib
import json
import os
import re
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

# Lock to ensure atomic thread-safe debug printing
print_lock = threading.Lock()


def parse_args():
    parser = argparse.ArgumentParser(
        description="Find cross-seeding opportunities via Prowlarr API focusing on Movies & TV Series."
    )
    parser.add_argument(
        "--config",
        "-c",
        help="Path to configuration file",
        default=None,
    )
    parser.add_argument(
        "--prowlarr-url",
        help="Prowlarr URL (overrides automatic K8s detection)",
        default=None,
    )
    parser.add_argument(
        "--api-key",
        help="Prowlarr API Key (overrides automatic K8s secret retrieval)",
        default=None,
    )
    parser.add_argument(
        "--target-indexer",
        "-t",
        help="Target indexer name (e.g. c411, ncore, chptv)",
        default=None,
    )
    parser.add_argument(
        "--direct-c411",
        action="store_true",
        help="Query C411 native API (https://c411.org/api) directly via cluster VPN pod curl to bypass Prowlarr's 100-release cap",
    )
    parser.add_argument(
        "--audit",
        action="store_true",
        help="Enable diagnostic audit mode reporting detailed breakdown of skipped items and match rejections",
    )
    parser.add_argument(
        "--categories",
        help="Comma-separated list of Torznab category IDs (default: '2000,5000' for Movies & TV Series)",
        default=None,
    )
    parser.add_argument(
        "--min-leechers",
        type=int,
        help="Minimum number of leechers required on target indexer",
        default=None,
    )
    parser.add_argument(
        "--max-ratio",
        type=float,
        help="Maximum seeders-to-leechers ratio threshold",
        default=None,
    )
    parser.add_argument(
        "--min-size-mb",
        type=float,
        help="Minimum release file size in Megabytes (e.g. 100 MB)",
        default=None,
    )
    parser.add_argument(
        "--max-size-gb",
        type=float,
        help="Maximum release file size in Gigabytes (e.g. 100 GB)",
        default=None,
    )
    parser.add_argument(
        "--max-scan-releases",
        type=int,
        help="Maximum total releases to scan from target indexer (default: 500)",
        default=None,
    )
    parser.add_argument(
        "--min-year",
        type=int,
        help="Minimum release year filter (e.g. 2025 to skip older releases)",
        default=None,
    )
    parser.add_argument(
        "--maxage",
        type=int,
        help="Maximum release age in days for upstream C411 query (default: 575 days for releases since 01/2025)",
        default=None,
    )
    parser.add_argument(
        "--threads",
        type=int,
        help="Number of parallel worker threads for searching secondary indexers (default: 5)",
        default=None,
    )
    parser.add_argument(
        "--output-json",
        "-o",
        nargs="?",
        const="cross_seed_opportunities.json",
        help="Export discovered cross-seed opportunities to a structured JSON file (default: cross_seed_opportunities.json)",
        default=None,
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable detailed verbose debug logging",
    )
    return parser.parse_args()


def load_env_file(filepath):
    """Load configuration variables from a file if it exists."""
    if not filepath or not os.path.isfile(filepath):
        return
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip().strip("'\"")
            if key not in os.environ:
                os.environ[key] = val


def fetch_prowlarr_key_from_k8s():
    """Dynamically retrieve Prowlarr API key from Kubernetes secret."""
    try:
        cmd = [
            "kubectl",
            "get",
            "secret",
            "-n",
            "media-server",
            "servarr-api-key",
            "-o",
            "jsonpath={.data.api-key}",
        ]
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        if out:
            return base64.b64decode(out.strip()).decode("utf-8")
    except Exception:
        pass
    return None


def fetch_k8s_vpn_pod_name():
    """Find the Prowlarr or qBittorrent pod in media-server namespace to execute curl via cluster VPN."""
    try:
        cmd = [
            "kubectl",
            "get",
            "pods",
            "-n",
            "media-server",
            "-l",
            "app.kubernetes.io/controller=prowlarr",
            "-o",
            "jsonpath={.items[0].metadata.name}",
        ]
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        if out:
            return out.decode("utf-8").strip()
    except Exception:
        pass

    try:
        cmd_alt = [
            "kubectl",
            "get",
            "pods",
            "-n",
            "media-server",
            "-l",
            "app.kubernetes.io/controller=qbittorrent",
            "-o",
            "jsonpath={.items[0].metadata.name}",
        ]
        out_alt = subprocess.check_output(cmd_alt, stderr=subprocess.DEVNULL)
        if out_alt:
            return out_alt.decode("utf-8").strip()
    except Exception:
        pass
    return None


def format_human_size(size_bytes):
    """Format bytes into human-readable string (e.g. 444.0 MB or 1.74 GB)."""
    if size_bytes < 1024 * 1024 * 1024:
        mb = round(size_bytes / (1024 * 1024), 1)
        return f"{mb} MB"
    else:
        gb = round(size_bytes / (1024 * 1024 * 1024), 2)
        return f"{gb} GB"


def extract_resolution(title):
    """Extract resolution tag from title (2160p, 1080p, 720p, 576p, 480p)."""
    title_upper = title.upper()
    if "2160P" in title_upper or "4K" in title_upper or "UHD" in title_upper:
        return "2160p"
    elif "1080P" in title_upper or "FHD" in title_upper:
        return "1080p"
    elif "720P" in title_upper or "HD" in title_upper:
        return "720p"
    elif "576P" in title_upper or "DVDRIP" in title_upper:
        return "576p"
    elif "480P" in title_upper:
        return "480p"
    return "UNKNOWN"


def extract_season_episode(title):
    """Extract Season and Episode pattern (e.g. S01E04 -> ('01', '04'))."""
    match = re.search(r"S(\d{1,2})E(\d{1,2})", title, re.IGNORECASE)
    if match:
        return match.group(1).zfill(2), match.group(2).zfill(2)
    match_alt = re.search(r"(\d{1,2})x(\d{1,2})", title, re.IGNORECASE)
    if match_alt:
        return match_alt.group(1).zfill(2), match_alt.group(2).zfill(2)
    return None, None


def clean_title_for_fuzzy(title):
    """Clean tech tags to isolate title core for fuzzy matching."""
    cleaned = re.sub(
        r"(S\d{1,2}E\d{1,2}|\d{1,2}x\d{1,2}|2160p|1080p|720p|576p|480p|WEB|WEBRip|WEB-DL|BluRay|HDLight|REMUX|HDR|DV|AAC|EAC3|AC3|x264|x265|H264|H265|HEVC|AV1|VOSTFR|VFF|VF2|VFQ|MULTI|CUSTOM|AD|Atmos)",
        " ",
        title,
        flags=re.IGNORECASE,
    )
    cleaned = re.sub(r"[\s\._\-\[\]\(\)]+", " ", cleaned).strip().lower()
    return cleaned


def is_title_fuzzy_compatible(target_title, match_title, min_ratio=0.70):
    """Fuzzy string matching + Season/Episode & Year parity validation."""
    t_season, t_ep = extract_season_episode(target_title)
    m_season, m_ep = extract_season_episode(match_title)

    if t_season and t_ep and m_season and m_ep:
        if t_season != m_season or t_ep != m_ep:
            return False, 0.0

    t_year = extract_release_year(target_title)
    m_year = extract_release_year(match_title)

    if t_year and m_year and t_year != m_year:
        return False, 0.0

    t_clean = clean_title_for_fuzzy(target_title)
    m_clean = clean_title_for_fuzzy(match_title)

    if not t_clean or not m_clean:
        return True, 1.0

    ratio = difflib.SequenceMatcher(None, t_clean, m_clean).ratio()
    return ratio >= min_ratio, round(ratio, 2)


def create_requests_session(retries=3, backoff_factor=1.5):
    """Create a requests session with automatic retries for transient HTTP timeouts."""
    session = requests.Session()
    retry_strategy = Retry(
        total=retries,
        backoff_factor=backoff_factor,
        status_forcelist=[429, 500, 502, 503, 504],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


def get_config(args):
    """Resolve configuration from args, env file, Kubernetes secrets, or env vars."""
    if args.config:
        load_env_file(args.config)
    elif os.getenv("CROSS_SEED_CONFIG_PATH"):
        load_env_file(os.getenv("CROSS_SEED_CONFIG_PATH"))
    else:
        for default_conf in ["configs/cross-seed-finder.conf", "cross-seed-finder.conf", "configs/cross-seed-finder.env"]:
            if os.path.isfile(default_conf):
                load_env_file(default_conf)
                break

    prowlarr_url = (
        args.prowlarr_url
        or os.getenv("PROWLARR_URL")
        or "http://localhost:9696"
    ).rstrip("/")

    api_key = args.api_key or os.getenv("PROWLARR_API_KEY")
    if not api_key:
        api_key = fetch_prowlarr_key_from_k8s()

    target_indexer = args.target_indexer or os.getenv("TARGET_INDEXER_NAME", "c411")

    categories_str = args.categories or os.getenv("CATEGORIES", "2000,5000")
    categories = [int(c.strip()) for c in categories_str.split(",") if c.strip().isdigit()]

    min_leechers = (
        args.min_leechers
        if args.min_leechers is not None
        else int(os.getenv("MIN_LEECHERS", "5"))
    )
    max_ratio = (
        args.max_ratio
        if args.max_ratio is not None
        else float(os.getenv("MAX_SEED_LEECH_RATIO", "1.0"))
    )
    min_size_mb = (
        args.min_size_mb
        if args.min_size_mb is not None
        else float(os.getenv("MIN_SIZE_MB", "100.0"))
    )
    max_size_gb = (
        args.max_size_gb
        if args.max_size_gb is not None
        else float(os.getenv("MAX_SIZE_GB", "100.0"))
    )
    max_scan_releases = (
        args.max_scan_releases
        if args.max_scan_releases is not None
        else int(os.getenv("MAX_SCAN_RELEASES", "500"))
    )
    threads = (
        args.threads
        if args.threads is not None
        else int(os.getenv("MAX_WORKER_THREADS", "5"))
    )
    max_size_diff_mb = float(os.getenv("MAX_SIZE_DIFF_MB", "1.0"))

    if not api_key:
        print("ERROR: Could not retrieve Prowlarr API key from Kubernetes secret or environment.", file=sys.stderr)
        sys.exit(1)

    min_year = (
        args.min_year
        if args.min_year is not None
        else int(os.getenv("MIN_YEAR", "0"))
    )
    maxage = (
        args.maxage
        if args.maxage is not None
        else int(os.getenv("MAX_AGE_DAYS", "575"))
    )
    vpn_pod_name = None
    if args.direct_c411:
        vpn_pod_name = fetch_k8s_vpn_pod_name()

    return {
        "prowlarr_url": prowlarr_url,
        "api_key": api_key,
        "target_indexer": target_indexer,
        "direct_c411": args.direct_c411,
        "vpn_pod_name": vpn_pod_name,
        "audit": args.audit,
        "categories": categories,
        "min_leechers": min_leechers,
        "max_ratio": max_ratio,
        "min_year": min_year,
        "maxage": maxage,
        "min_size_bytes": int(min_size_mb * 1024 * 1024),
        "max_size_bytes": int(max_size_gb * 1024 * 1024 * 1024),
        "min_size_mb": min_size_mb,
        "max_size_gb": max_size_gb,
        "max_scan_releases": max_scan_releases,
        "threads": threads,
        "max_size_diff_bytes": int(max_size_diff_mb * 1024 * 1024),
        "output_json": args.output_json,
        "verbose": args.verbose,
    }


def fetch_indexers(session, prowlarr_url, api_key):
    """Fetch all configured indexers from Prowlarr."""
    headers = {"X-Api-Key": api_key, "Content-Type": "application/json"}
    url = f"{prowlarr_url}/api/v1/indexer"
    response = session.get(url, headers=headers, timeout=15)
    response.raise_for_status()
    return response.json()


def fetch_c411_native_key(session, prowlarr_url, api_key, target_indexer_name="c411"):
    """Fetch native C411 API key configured inside Prowlarr."""
    indexers = fetch_indexers(session, prowlarr_url, api_key)
    for idx in indexers:
        if target_indexer_name.lower() in idx["name"].lower():
            for f in idx.get("fields", []):
                if f["name"] == "apikey" and f.get("value"):
                    return f.get("value")
    return None


def extract_release_year(title, pub_date_str=None):
    """Extract release year from title (e.g. 2026, 2025) or fallback to pubDate year."""
    match = re.search(r"\b(19\d{2}|20\d{2})\b", title)
    if match:
        return int(match.group(1))
    if pub_date_str:
        match_pub = re.search(r"\b(19\d{2}|20\d{2})\b", str(pub_date_str))
        if match_pub:
            return int(match_pub.group(1))
    return None


def parse_torznab_xml(xml_text):
    """Parse Torznab XML response into structured release items."""
    items = []
    try:
        root = ET.fromstring(xml_text)
        channel = root.find("channel")
        if channel is None:
            return items

        torznab_ns = "http://torznab.com/schemas/2015/feed"

        for elem in channel.findall("item"):
            title = elem.findtext("title") or "Unknown"
            size = int(elem.findtext("size") or 0)
            pub_date = elem.findtext("pubDate") or ""

            seeders = 0
            leechers = 0
            info_hash = ""
            imdb_id = None
            tvdb_id = None
            tmdb_id = None

            for attr in elem.findall(f"{{{torznab_ns}}}attr"):
                name = attr.get("name")
                val = attr.get("value")
                if name == "seeders":
                    seeders = int(val or 0)
                elif name == "peers" or name == "leechers":
                    leechers = int(val or 0)
                elif name == "infohash":
                    info_hash = val.lower() if val else ""
                elif name == "imdb" or name == "imdbid":
                    imdb_id = val.replace("tt", "") if val else None
                elif name == "tvdb" or name == "tvdbid":
                    tvdb_id = val
                elif name == "tmdb" or name == "tmdbid":
                    tmdb_id = val

            items.append({
                "title": title,
                "size": size,
                "seeders": seeders,
                "leechers": leechers,
                "infoHash": info_hash,
                "imdbId": imdb_id,
                "tvdbId": tvdb_id,
                "tmdbId": tmdb_id,
                "pubDate": pub_date,
            })
    except Exception:
        pass
    return items


def fetch_target_page(session, config, target_indexer_id, offset=0, page_size=100, c411_native_key=None):
    """
    Fetch 1 single page from target indexer.
    If direct_c411=True, executes `kubectl exec curl` inside Prowlarr VPN pod to query https://c411.org/api directly.
    """
    cat_param = ",".join(str(c) for c in config["categories"])
    maxage_param = f"&maxage={config['maxage']}" if config.get("maxage") and config["maxage"] > 0 else ""

    if config["direct_c411"] and c411_native_key and config["vpn_pod_name"]:
        target_url = f"https://c411.org/api?t=search&cat={cat_param}&extended=1&sort=peers{maxage_param}&limit={page_size}&offset={offset}&apikey={c411_native_key}"
        try:
            cmd = [
                "kubectl",
                "exec",
                "-n",
                "media-server",
                config["vpn_pod_name"],
                "-c",
                "main",
                "--",
                "curl",
                "-s",
                "-m",
                "25",
                target_url,
            ]
            out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
            if out:
                return parse_torznab_xml(out.decode("utf-8", errors="ignore"))
        except Exception as e:
            print(f"WARNING: kubectl exec curl failed at offset {offset}: {e}", file=sys.stderr)
            return []
    else:
        url = f"{config['prowlarr_url']}/{target_indexer_id}/api"
        params = {
            "t": "search",
            "cat": cat_param,
            "extended": 1,
            "limit": page_size,
            "offset": offset,
            "apikey": config["api_key"],
        }
        try:
            response = session.get(url, params=params, timeout=30)
            response.raise_for_status()
            return parse_torznab_xml(response.text)
        except Exception as e:
            print(f"WARNING: Failed fetching Torznab page at offset {offset}: {e}", file=sys.stderr)
            return []


def search_secondary_indexer(session, prowlarr_url, api_key, indexer_ids, categories, query=None, imdb_id=None, tvdb_id=None, tmdb_id=None, limit=100):
    """Query secondary indexers via Prowlarr API using query string or media IDs."""
    headers = {"X-Api-Key": api_key, "Content-Type": "application/json"}
    url = f"{prowlarr_url}/api/v1/search"

    params = [("type", "search"), ("limit", limit)]
    for idx in indexer_ids:
        params.append(("indexerIds", idx))
    for cat in categories:
        params.append(("categories", cat))

    if imdb_id and str(imdb_id) != "0":
        params.append(("imdbId", imdb_id))
    elif tvdb_id and str(tvdb_id) != "0":
        params.append(("tvdbId", tvdb_id))
    elif tmdb_id and str(tmdb_id) != "0":
        params.append(("tmdbId", tmdb_id))
    elif query:
        params.append(("query", query))

    response = session.get(url, headers=headers, params=params, timeout=45)
    response.raise_for_status()
    return response.json()


def evaluate_candidate(candidate_index, rel, config, other_indexer_ids, session):
    """Evaluate a single candidate release against other indexers."""
    title = rel.get("title", "Unknown Title")
    seeders = rel.get("seeders", 0)
    leechers = rel.get("leechers", 0)
    size = rel.get("size", 0)
    info_hash = rel.get("infoHash", "").lower()
    imdb_id = rel.get("imdbId")
    tvdb_id = rel.get("tvdbId")
    tmdb_id = rel.get("tmdbId")
    ratio = seeders / leechers if leechers > 0 else 999.0
    verbose = config["verbose"]
    categories = config["categories"]
    target_res = extract_resolution(title)
    human_size = format_human_size(size)

    audit_details = {
        "title": title,
        "search_returned_zero": False,
        "rejected_fuzzy_title": [],
        "rejected_resolution": [],
        "rejected_size_diff": [],
    }

    log_lines = []
    if verbose:
        ids_info = []
        if imdb_id and str(imdb_id) != "0": ids_info.append(f"IMDb: tt{imdb_id}")
        if tvdb_id and str(tvdb_id) != "0": ids_info.append(f"TVDb: {tvdb_id}")
        if tmdb_id and str(tmdb_id) != "0": ids_info.append(f"TMDb: {tmdb_id}")
        ids_str = f" | {', '.join(ids_info)}" if ids_info else ""
        log_lines.append(f"[CANDIDATE #{candidate_index}] {title}")
        log_lines.append(f"  └─ Target Stats: {seeders}s/{leechers}l (Ratio {ratio:.2f}) | Res: {target_res} | Size: {human_size}{ids_str}")

    matches = []
    search_error = None
    try:
        if imdb_id and str(imdb_id) != "0":
            if verbose: log_lines.append(f"  └─ Searching by IMDb ID tt{imdb_id}...")
            matches = search_secondary_indexer(session, config["prowlarr_url"], config["api_key"], other_indexer_ids, categories, imdb_id=imdb_id)

        if not matches and tvdb_id and str(tvdb_id) != "0":
            if verbose: log_lines.append(f"  └─ Searching by TVDb ID {tvdb_id}...")
            matches = search_secondary_indexer(session, config["prowlarr_url"], config["api_key"], other_indexer_ids, categories, tvdb_id=tvdb_id)

        if not matches and tmdb_id and str(tmdb_id) != "0":
            if verbose: log_lines.append(f"  └─ Searching by TMDb ID {tmdb_id}...")
            matches = search_secondary_indexer(session, config["prowlarr_url"], config["api_key"], other_indexer_ids, categories, tmdb_id=tmdb_id)

        if not matches:
            if verbose: log_lines.append(f"  └─ Searching by Title: {title[:40]}...")
            matches = search_secondary_indexer(session, config["prowlarr_url"], config["api_key"], other_indexer_ids, categories, query=title)

    except Exception as e:
        search_error = str(e)
        if verbose:
            log_lines.append(f"  └─ [ERROR] Search failed for '{title[:40]}': {e}")
        else:
            with print_lock:
                print(f"WARNING: Search timed out or failed for candidate #{candidate_index} ('{title[:45]}'): {e}", file=sys.stderr)
        matches = []

    if not matches:
        audit_details["search_returned_zero"] = True

    matching_results = []
    for match in matches:
        match_title = match.get("title", "")
        match_size = match.get("size", 0)
        match_hash = match.get("infoHash", "").lower()
        match_indexer = match.get("indexer", "Unknown")
        match_res = extract_resolution(match_title)
        match_human_size = format_human_size(match_size)
        size_diff = abs(match_size - size)

        # 1. Exact InfoHash Match
        if info_hash and match_hash and info_hash == match_hash:
            matching_results.append({
                "indexer": match_indexer,
                "type": "HASH 🎯",
                "matched_title": match_title,
                "matched_size": match_human_size,
                "resolution": match_res,
            })
            if verbose:
                log_lines.append(f"  └─ [MATCH HASH 🎯] Tracker: '{match_indexer}' | Size: {match_human_size}")
                log_lines.append(f"     └─ Matched Title: {match_title}")

        # 2. Size Match AND Resolution Match AND Fuzzy Title Compatibility
        elif size_diff <= config["max_size_diff_bytes"]:
            is_compat, fuzzy_score = is_title_fuzzy_compatible(title, match_title, min_ratio=0.35)
            if not is_compat:
                audit_details["rejected_fuzzy_title"].append({"indexer": match_indexer, "title": match_title, "score": fuzzy_score})
                if verbose:
                    log_lines.append(f"  └─ [REJECT FUZZY TITLE] '{match_indexer}' (Score: {fuzzy_score}) | '{title[:30]}' != '{match_title[:30]}'")
            elif target_res != "UNKNOWN" and match_res != "UNKNOWN" and target_res != match_res:
                audit_details["rejected_resolution"].append({"indexer": match_indexer, "title": match_title, "target_res": target_res, "match_res": match_res})
                if verbose:
                    log_lines.append(f"  └─ [REJECT RESOLUTION] '{match_indexer}' | Target Res ({target_res}) != Match Res ({match_res})")
            else:
                matching_results.append({
                    "indexer": match_indexer,
                    "type": "SIZE 🟢",
                    "matched_title": match_title,
                    "matched_size": match_human_size,
                    "resolution": match_res,
                    "size_diff_kb": round(size_diff / 1024, 1),
                    "fuzzy_score": fuzzy_score,
                })
                if verbose:
                    log_lines.append(f"  └─ [MATCH SIZE 🟢] Tracker: '{match_indexer}' | Size: {match_human_size} (Diff: {round(size_diff / 1024, 1)} KB) | Fuzzy: {fuzzy_score} | Res: {match_res}")
                    log_lines.append(f"     └─ Matched Title: {match_title}")
        else:
            audit_details["rejected_size_diff"].append({"indexer": match_indexer, "title": match_title, "target_size": human_size, "match_size": match_human_size, "diff_mb": round(size_diff / (1024*1024), 1)})

    if verbose and log_lines:
        with print_lock:
            print("\n".join(log_lines))

    if matching_results:
        return {
            "target_title": title,
            "target_size": human_size,
            "target_size_bytes": size,
            "seeders": seeders,
            "leechers": leechers,
            "ratio": round(ratio, 2),
            "resolution": target_res,
            "imdbId": f"tt{imdb_id}" if imdb_id else None,
            "tvdbId": tvdb_id,
            "tmdbId": tmdb_id,
            "infoHash": info_hash,
            "matches_detail": matching_results,
            "audit_details": audit_details,
            "error": None,
        }

    return {"target_title": title, "audit_details": audit_details, "error": search_error}


def export_opportunities_to_json(filepath, opportunities, summary_stats, audit_stats=None):
    """Export opportunities array and execution stats to a JSON file."""
    data = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "summary": summary_stats,
        "audit": audit_stats,
        "opportunities": opportunities,
    }
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"\n📁 Successfully exported {len(opportunities)} cross-seed opportunities to JSON file: {filepath}")


def main():
    start_time = time.time()
    args = parse_args()
    config = get_config(args)
    verbose = config["verbose"]
    session = create_requests_session(retries=3, backoff_factor=1.5)

    print("==================================================")
    print(" Multi-Threaded Prowlarr Cross-Seed Opportunity Finder")
    print("==================================================")
    print(f"Prowlarr URL          : {config['prowlarr_url']}")
    print(f"Target Indexer        : {config['target_indexer']}")
    if config["direct_c411"]:
        print(f"Direct C411 Egress    : ENABLED via kubectl exec curl (Pod: {config['vpn_pod_name']})")
    else:
        print(f"Direct C411 Egress    : DISABLED (Prowlarr Proxy)")
    print(f"Audit Diagnostic Mode : {'ENABLED' if config['audit'] else 'DISABLED'}")
    print(f"Target Categories     : Movies (2000), TV Series (5000)")
    print(f"Min Leechers Threshold: {config['min_leechers']}")
    print(f"Max Seed/Leech Ratio  : {config['max_ratio']}")
    print(f"File Size Range       : {config['min_size_mb']} MB to {config['max_size_gb']} GB")
    print(f"Max Scan Limit        : {config['max_scan_releases']} releases (paginated)")
    print(f"Parallel Worker Threads: {config['threads']}")
    if config["output_json"]:
        print(f"JSON Export Target    : {config['output_json']}")
    print(f"Verbose Debug Mode    : {'ENABLED' if verbose else 'DISABLED'}")
    print("==================================================\n")

    try:
        indexers = fetch_indexers(session, config["prowlarr_url"], config["api_key"])
    except Exception as e:
        print(f"ERROR: Failed to connect to Prowlarr API at {config['prowlarr_url']}: {e}", file=sys.stderr)
        sys.exit(1)

    target_indexer_id = None
    other_indexers = []

    for idx in indexers:
        if config["target_indexer"].lower() in idx["name"].lower():
            target_indexer_id = idx["id"]
        else:
            other_indexers.append(idx)

    if not target_indexer_id:
        print(f"ERROR: Target indexer '{config['target_indexer']}' not found in Prowlarr.", file=sys.stderr)
        print("Available indexers:", ", ".join(i["name"] for i in indexers))
        sys.exit(1)

    c411_native_key = None
    if config["direct_c411"]:
        c411_native_key = fetch_c411_native_key(session, config["prowlarr_url"], config["api_key"], config["target_indexer"])
        if not c411_native_key:
            print("WARNING: Could not extract native C411 API key from Prowlarr config. Falling back to Prowlarr proxy.", file=sys.stderr)
            config["direct_c411"] = False

    other_indexer_ids = [i["id"] for i in other_indexers]
    other_indexer_names = [i["name"] for i in other_indexers]

    if verbose:
        print(f"[DEBUG] Target Indexer: {config['target_indexer']} (ID: {target_indexer_id})")
        print(f"[DEBUG] Other Indexers ({len(other_indexer_ids)}): {', '.join(other_indexer_names)}\n")

    # Audit Counters
    audit_skipped_leechers = 0
    audit_skipped_ratio = 0
    audit_skipped_size = 0
    audit_zero_search_results = 0
    audit_rejected_fuzzy_title = 0
    audit_rejected_resolution = 0
    audit_rejected_size_diff = 0

    total_scanned = 0
    total_candidates = 0
    opportunities = []
    error_count = 0
    offset = 0
    page_size = 100
    page_number = 1

    scan_mode_str = f"Direct C411 via Pod Egress ({config['vpn_pod_name']})" if config["direct_c411"] else "Prowlarr Proxy"
    print(f"Starting Sequential Page-by-Page Discovery & Evaluation Pipeline ({scan_mode_str})...\n")

    while total_scanned < config["max_scan_releases"]:
        print(f"--- [PAGE #{page_number}] Fetching releases (Offset {offset})... ---")
        batch = fetch_target_page(
            session,
            config,
            target_indexer_id,
            offset=offset,
            page_size=page_size,
            c411_native_key=c411_native_key,
        )
        if not batch:
            print("No more releases returned from target indexer.")
            break

        total_scanned += len(batch)

        # Filter candidate releases for this batch
        page_candidates = []
        for rel in batch:
            seeders = rel.get("seeders", 0)
            leechers = rel.get("leechers", 0)
            size = rel.get("size", 0)
            ratio = seeders / leechers if leechers > 0 else 999.0

            if leechers < config["min_leechers"]:
                audit_skipped_leechers += 1
                continue
            if ratio > config["max_ratio"]:
                audit_skipped_ratio += 1
                continue
            if size < config["min_size_bytes"] or size > config["max_size_bytes"]:
                audit_skipped_size += 1
                continue
            if config["min_year"] > 0:
                rel_year = extract_release_year(rel.get("title", ""), rel.get("pubDate", ""))
                if rel_year and rel_year < config["min_year"]:
                    if verbose:
                        print(f"[DEBUG SKIP YEAR] Year ({rel_year}) < min_year ({config['min_year']}): {rel.get('title', '')[:50]}")
                    continue
            page_candidates.append(rel)

        total_candidates += len(page_candidates)
        print(f"  └─ Fetched {len(batch)} releases. Found {len(page_candidates)} candidate(s) meeting thresholds.")

        # Sort candidates by leechers (and seeders) descending so torrents with the biggest swarm demand are ALWAYS evaluated FIRST
        page_candidates.sort(key=lambda rel: (rel.get("leechers", 0), rel.get("seeders", 0)), reverse=True)

        # Evaluate this page's candidates in parallel across secondary indexers
        if page_candidates:
            print(f"  └─ Evaluating {len(page_candidates)} candidate(s) across secondary indexers...")
            with ThreadPoolExecutor(max_workers=config["threads"]) as executor:
                future_to_rel = {
                    executor.submit(evaluate_candidate, total_candidates - len(page_candidates) + idx + 1, rel, config, other_indexer_ids, session): rel
                    for idx, rel in enumerate(page_candidates)
                }
                for future in as_completed(future_to_rel):
                    res = future.result()
                    if res and res.get("audit_details"):
                        ad = res["audit_details"]
                        if ad["search_returned_zero"]: audit_zero_search_results += 1
                        audit_rejected_fuzzy_title += len(ad["rejected_fuzzy_title"])
                        audit_rejected_resolution += len(ad["rejected_resolution"])
                        audit_rejected_size_diff += len(ad["rejected_size_diff"])

                    if res and res.get("error"):
                        error_count += 1
                    elif res and res.get("matches_detail"):
                        opportunities.append(res)

        offset += len(batch)
        page_number += 1

        if len(batch) < page_size:
            break

        time.sleep(1.0)

    opportunities.sort(key=lambda x: (x["ratio"], -x["leechers"]))
    elapsed_time = round(time.time() - start_time, 2)

    summary_stats = {
        "target_indexer": config["target_indexer"],
        "scan_mode": scan_mode_str,
        "total_releases_scanned": total_scanned,
        "candidates_meeting_thresholds": total_candidates,
        "errors_count": error_count,
        "cross_seed_matches_found": len(opportunities),
        "execution_time_seconds": elapsed_time,
    }

    audit_stats = {
        "skipped_low_leechers": audit_skipped_leechers,
        "skipped_high_ratio": audit_skipped_ratio,
        "skipped_size_out_of_bounds": audit_skipped_size,
        "candidates_searched_returned_zero": audit_zero_search_results,
        "secondary_matches_rejected_fuzzy_title": audit_rejected_fuzzy_title,
        "secondary_matches_rejected_resolution": audit_rejected_resolution,
        "secondary_matches_rejected_size_diff": audit_rejected_size_diff,
    }

    print("\n==================================================")
    print(" Execution Diagnostics & Summary")
    print("==================================================")
    print(f"Target Indexer Mode       : {scan_mode_str}")
    print(f"Total Releases Scanned    : {total_scanned}")
    print(f"Met Thresholds (Leech/Ratio/Size): {total_candidates}")
    print(f"Search Timeouts / Errors  : {error_count}")
    print(f"Cross-Seed Matches Found  : {len(opportunities)}")
    print(f"Total Execution Time      : {elapsed_time} seconds")
    print("==================================================")

    if config["audit"]:
        print("\n==================================================")
        print(" 🔬 Detailed Audit Diagnostic Breakdown")
        print("==================================================")
        print(f"Releases Skipped (< {config['min_leechers']} Leechers)    : {audit_skipped_leechers}")
        print(f"Releases Skipped (> {config['max_ratio']} Seed/Leech)  : {audit_skipped_ratio}")
        print(f"Releases Skipped (Size Out of Bounds)   : {audit_skipped_size}")
        print(f"Candidates with 0 Secondary Results     : {audit_zero_search_results}")
        print(f"Secondary Torrents Rejected (Fuzzy Title): {audit_rejected_fuzzy_title}")
        print(f"Secondary Torrents Rejected (Resolution): {audit_rejected_resolution}")
        print(f"Secondary Torrents Rejected (Size > 1MB): {audit_rejected_size_diff}")
        print("==================================================\n")

    if config["output_json"]:
        export_opportunities_to_json(config["output_json"], opportunities, summary_stats, audit_stats if config["audit"] else None)

    if not opportunities:
        print("No cross-seed opportunities matching criteria were found.")
        if not verbose:
            print("Tip: Run with --verbose (-v) or --audit to see detailed diagnostic logs.")
        return

    print(f"Found {len(opportunities)} Cross-Seed Opportunity Candidate(s):\n")

    for idx, op in enumerate(opportunities, 1):
        ratio_str = f"{op['seeders']}s/{op['leechers']}l (Ratio {op['ratio']})"
        print(f"[{idx}] Target C411: {op['target_title']}")
        print(f"    Size: {op['target_size']} | Stats: {ratio_str} | Res: {op['resolution']}")
        print("    Matched Secondary Releases:")
        for m in op["matches_detail"]:
            print(f"      └─ [{m['type']}] {m['indexer']} ({m['matched_size']}) -> Title: {m['matched_title']}")
        print("-" * 100)


if __name__ == "__main__":
    main()
