#!/usr/bin/env python3
"""Download and convert the FreeDict English/Portuguese dictionaries.

The generated JSON is deliberately simple so the Swift app can load it with
Foundation.JSONDecoder without depending on a StarDict parser.  Each lookup
key maps to a list because FreeDict stores one or more senses for many words.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import html
import json
import re
import tarfile
import tempfile
import urllib.request
from collections.abc import Iterable
from html.parser import HTMLParser
from pathlib import Path

PAIRS = {
    "en-pt": {
        "archive": "https://download.freedict.org/dictionaries/eng-por/0.3/freedict-eng-por-0.3.stardict.tar.xz",
        "root": "eng-por",
        "basename": "eng-por",
        "source_language": "en",
        "target_language": "pt",
        "version": "0.3",
        "headwords": 15773,
    },
    "pt-en": {
        "archive": "https://download.freedict.org/dictionaries/por-eng/0.2/freedict-por-eng-0.2.stardict.tar.xz",
        "root": "por-eng",
        "basename": "por-eng",
        "source_language": "pt",
        "target_language": "en",
        "version": "0.2",
        "headwords": 10661,
    },
}


class EntryHTMLParser(HTMLParser):
    """Reduce FreeDict's small HTML records to ordered sense strings."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._current: list[str] = []
        self._senses: list[str] = []
        self._skip_font = 0

    def _flush(self) -> None:
        value = re.sub(r"\s+", " ", "".join(self._current)).strip()
        value = re.sub(r"^/+|/+$", "", value).strip()
        if value and value not in self._senses:
            self._senses.append(value)
        self._current.clear()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        # FreeDict uses gray for pronunciation and green for grammatical
        # labels (adjective, noun, ...). Neither is a translation sense.
        if tag == "font":
            self._skip_font += 1
        elif tag == "li" or tag == "br":
            self._flush()

    def handle_endtag(self, tag: str) -> None:
        if tag == "font" and self._skip_font:
            self._skip_font -= 1
        elif tag == "li":
            self._flush()

    def handle_data(self, data: str) -> None:
        if not self._skip_font:
            self._current.append(data)

    def finish(self) -> list[str]:
        self._flush()
        return self._senses


def parse_index(index_data: bytes) -> Iterable[tuple[str, int, int]]:
    cursor = 0
    while cursor < len(index_data):
        end = index_data.find(b"\0", cursor)
        if end < 0 or end + 9 > len(index_data):
            break
        word = index_data[cursor:end].decode("utf-8", "replace")
        offset = int.from_bytes(index_data[end + 1 : end + 5], "big")
        size = int.from_bytes(index_data[end + 5 : end + 9], "big")
        yield word, offset, size
        cursor = end + 9


def parse_dictionary(index_data: bytes, dictionary_data: bytes) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for word, offset, size in parse_index(index_data):
        parser = EntryHTMLParser()
        parser.feed(dictionary_data[offset : offset + size].decode("utf-8", "replace"))
        senses = [html.unescape(s) for s in parser.finish()]
        if senses:
            result.setdefault(word, [])
            for sense in senses:
                if sense not in result[word]:
                    result[word].append(sense)
    return dict(sorted(result.items(), key=lambda item: item[0].casefold()))


def download(url: str, destination: Path) -> str:
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    destination.write_bytes(data)
    return hashlib.sha512(data).hexdigest()


def convert(pair_name: str, output_dir: Path, archive: Path | None = None) -> Path:
    metadata = PAIRS[pair_name]
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="freedict-") as temporary:
        archive_path = Path(temporary) / "dictionary.tar.xz"
        if archive is None:
            archive_sha512 = download(metadata["archive"], archive_path)
        else:
            archive_path = archive
            archive_sha512 = hashlib.sha512(archive_path.read_bytes()).hexdigest()
        with tarfile.open(archive_path, mode="r:xz") as package:
            dictionary_path = f"{metadata['root']}/{metadata['basename']}.dict.dz"
            index_path = f"{metadata['root']}/{metadata['basename']}.idx.gz"
            dictionary_data = gzip.decompress(package.extractfile(dictionary_path).read())
            index_data = gzip.decompress(package.extractfile(index_path).read())
            copying = package.extractfile(f"{metadata['root']}/COPYING").read()
            (output_dir / f"{pair_name}-COPYING").write_bytes(copying)
        entries = parse_dictionary(index_data, dictionary_data)
    payload = {
        "schema_version": 1,
        "source_language": metadata["source_language"],
        "target_language": metadata["target_language"],
        "language_variant": "Portuguese (generic; not guaranteed pt-BR)",
        "source": "FreeDict",
        "source_url": metadata["archive"],
        "version": metadata["version"],
        "license": "GPL-2.0-or-later",
        "archive_sha512": archive_sha512,
        "entry_count": len(entries),
        "entries": entries,
    }
    destination = output_dir / f"freedict-{pair_name}.json"
    destination.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    # Keep generated data in the SwiftPM resource directory. The repository
    # root owns this maintenance script and documentation; the app owns one
    # authoritative copy of the generated dictionaries.
    default_output_dir = Path(__file__).parents[3] / "Sources" / "TranslateBarApp" / "Resources" / "FreeDict" / "data"
    parser.add_argument("--output-dir", type=Path, default=default_output_dir)
    parser.add_argument("--pair", choices=["en-pt", "pt-en"], action="append")
    parser.add_argument("--archive", type=Path, action="append", help="local archive, in the same order as --pair")
    args = parser.parse_args()
    pairs = args.pair or list(PAIRS)
    archives = args.archive or []
    if archives and len(archives) != len(pairs):
        parser.error("--archive must be supplied once for each --pair")
    for index, pair_name in enumerate(pairs):
        archive = archives[index] if archives else None
        print(convert(pair_name, args.output_dir, archive))


if __name__ == "__main__":
    main()
