from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
import math
import unicodedata


_REPO_ROOT = Path(__file__).resolve().parents[3]
_DATA_DIR = _REPO_ROOT / "docs" / "data"
_CITY_DATA_PATH = _DATA_DIR / "geonames_cities5000.txt"
_ADMIN1_DATA_PATH = _DATA_DIR / "admin1CodesASCII.txt"
_COUNTRY_DATA_PATH = _DATA_DIR / "countryInfo.txt"


@dataclass(frozen=True)
class CitySearchEntry:
    geoname_id: int
    name: str
    display_name: str
    latitude: float
    longitude: float
    country_code: str
    country_name: str
    admin1_code: str | None
    admin1_name: str | None
    population: int
    search_blob: str
    name_key: str
    display_key: str


def _normalize_search_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    return " ".join(ascii_value.casefold().split())


@lru_cache(maxsize=1)
def _country_lookup() -> dict[str, str]:
    if not _COUNTRY_DATA_PATH.exists():
        return {}

    lookup: dict[str, str] = {}
    with _COUNTRY_DATA_PATH.open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 5:
                continue
            iso_code = fields[0].strip()
            country_name = fields[4].strip()
            if iso_code and country_name:
                lookup[iso_code] = country_name
    return lookup


@lru_cache(maxsize=1)
def _admin1_lookup() -> dict[str, str]:
    if not _ADMIN1_DATA_PATH.exists():
        return {}

    lookup: dict[str, str] = {}
    with _ADMIN1_DATA_PATH.open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 2:
                continue
            key = fields[0].strip()
            name = fields[1].strip() or (fields[2].strip() if len(fields) > 2 else "")
            if key and name:
                lookup[key] = name
    return lookup


def _build_display_name(name: str, admin1_name: str | None, country_name: str) -> str:
    parts = [name]
    if admin1_name and admin1_name not in name:
        parts.append(admin1_name)
    if country_name and country_name not in name:
        parts.append(country_name)
    return ", ".join(parts)


@lru_cache(maxsize=1)
def load_city_entries() -> tuple[CitySearchEntry, ...]:
    if not _CITY_DATA_PATH.exists():
        return ()

    country_lookup = _country_lookup()
    admin1_lookup = _admin1_lookup()
    entries: list[CitySearchEntry] = []

    with _CITY_DATA_PATH.open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) < 19:
                continue

            feature_class = fields[6].strip()
            if feature_class != "P":
                continue

            try:
                geoname_id = int(fields[0])
                latitude = float(fields[4])
                longitude = float(fields[5])
                population = int(fields[14] or 0)
            except ValueError:
                continue

            name = fields[2].strip() or fields[1].strip()
            if not name:
                continue

            country_code = fields[8].strip()
            country_name = country_lookup.get(country_code, country_code or "Unknown")
            admin1_code = fields[10].strip() or None
            admin1_name = None
            if admin1_code and country_code:
                admin1_name = admin1_lookup.get(f"{country_code}.{admin1_code}")

            display_name = _build_display_name(name, admin1_name, country_name)
            search_blob = _normalize_search_text(
                " ".join(
                    part
                    for part in [
                        name,
                        fields[1].strip(),
                        admin1_name or "",
                        country_name,
                    ]
                    if part
                )
            )

            entries.append(
                CitySearchEntry(
                    geoname_id=geoname_id,
                    name=name,
                    display_name=display_name,
                    latitude=latitude,
                    longitude=longitude,
                    country_code=country_code,
                    country_name=country_name,
                    admin1_code=admin1_code,
                    admin1_name=admin1_name,
                    population=population,
                    search_blob=search_blob,
                    name_key=_normalize_search_text(name),
                    display_key=_normalize_search_text(display_name),
                )
            )

    entries.sort(key=lambda entry: entry.population, reverse=True)
    return tuple(entries)


def _search_score(entry: CitySearchEntry, query: str, tokens: list[str]) -> float:
    score = math.log10(max(entry.population, 1))

    if entry.display_key == query:
        score += 200
    elif entry.name_key == query:
        score += 180
    elif entry.display_key.startswith(query):
        score += 120
    elif entry.name_key.startswith(query):
        score += 110
    elif query in entry.display_key:
        score += 70
    elif query in entry.name_key:
        score += 60

    if tokens:
        if all(token in entry.search_blob for token in tokens):
            score += 50
        for token in tokens:
            if entry.name_key.startswith(token):
                score += 12
            elif token in entry.name_key:
                score += 8
            elif token in entry.search_blob:
                score += 4

    return score


def search_city_entries(query: str, limit: int = 12) -> list[CitySearchEntry]:
    entries = load_city_entries()
    if not entries:
        return []

    normalized_query = _normalize_search_text(query)
    if not normalized_query:
        return list(entries[:limit])

    tokens = normalized_query.split()
    scored: list[tuple[float, CitySearchEntry]] = []
    for entry in entries:
        if not any(token in entry.search_blob for token in tokens):
            continue
        scored.append((_search_score(entry, normalized_query, tokens), entry))

    scored.sort(
        key=lambda item: (
            item[0],
            item[1].population,
            item[1].display_name,
        ),
        reverse=True,
    )
    return [entry for _, entry in scored[:limit]]
