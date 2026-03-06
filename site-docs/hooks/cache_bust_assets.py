from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import re


DOCS_DIR = Path(__file__).resolve().parents[1]
ASSET_PATHS = (
    "stylesheets/extra.css",
    "javascripts/home-carousel.js",
)


def _asset_version(relative_path: str) -> str:
    asset_path = DOCS_DIR / relative_path
    return sha256(asset_path.read_bytes()).hexdigest()[:10]


ASSET_VERSIONS = {path: _asset_version(path) for path in ASSET_PATHS}
ASSET_PATTERNS = {
    path: re.compile(
        rf'(?P<prefix>(?:href|src)=["\'])(?P<path>(?:\.\./)*{re.escape(path)})(?P<suffix>["\'])'
    )
    for path in ASSET_PATHS
}


def on_post_page(output: str, page, config) -> str:
    for path, pattern in ASSET_PATTERNS.items():
        version = ASSET_VERSIONS[path]
        output = pattern.sub(
            lambda match: (
                f"{match.group('prefix')}{match.group('path')}?v={version}{match.group('suffix')}"
            ),
            output,
        )
    return output
