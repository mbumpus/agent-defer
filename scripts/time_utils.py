#!/usr/bin/env python3

import argparse
import os
import re
import sys
from datetime import datetime, time, timedelta

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None


COMPACT_DURATION_RE = re.compile(
    r"^(?:(?P<w>\d+)w)?(?:(?P<d>\d+)d)?(?:(?P<h>\d+)h)?(?:(?P<m>\d+)m)?(?:(?P<s>\d+)s)?$",
    re.IGNORECASE,
)
VERBOSE_DURATION_RE = re.compile(
    r"(?P<value>\d+)\s*(?P<unit>weeks?|days?|hours?|hrs?|minutes?|mins?|seconds?|secs?)",
    re.IGNORECASE,
)
WEEKDAY_INDEX = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}
TIMEZONE_TOKENS = {
    "utc",
    "gmt",
    "est",
    "edt",
    "cst",
    "cdt",
    "mst",
    "mdt",
    "pst",
    "pdt",
    "cet",
    "cest",
    "eet",
    "eest",
    "bst",
    "ist",
    "jst",
    "aest",
    "aedt",
    "akst",
    "akdt",
    "hst",
}


def local_tz():
    tz_name = os.environ.get("DEFER_TIMEZONE") or os.environ.get("TZ")
    if tz_name and ZoneInfo is not None:
        try:
            return ZoneInfo(tz_name)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo


def as_utc_iso(value):
    return value.astimezone(ZoneInfo("UTC") if ZoneInfo else value.astimezone().tzinfo).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def parse_iso(raw, tzinfo):
    text = raw.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=tzinfo)
    return parsed


def parse_clock(raw):
    text = raw.strip().lower().replace(".", "")
    text = re.sub(r"\s+", " ", text)
    if text == "noon":
        return time(12, 0)
    if text == "midnight":
        return time(0, 0)
    text = re.sub(r"(\d)\s*(am|pm)$", r"\1\2", text)
    for fmt in ("%I%p", "%I:%M%p", "%H:%M", "%H%M"):
        try:
            return datetime.strptime(text, fmt).time()
        except ValueError:
            continue
    raise ValueError(f"Unsupported clock time: {raw}")


def parse_compact_duration(raw):
    match = COMPACT_DURATION_RE.fullmatch(raw.strip())
    if not match or not any(match.groupdict().values()):
        return None
    parts = {key: int(value or 0) for key, value in match.groupdict().items()}
    return timedelta(
        weeks=parts["w"],
        days=parts["d"],
        hours=parts["h"],
        minutes=parts["m"],
        seconds=parts["s"],
    )


def parse_verbose_duration(raw):
    matches = list(VERBOSE_DURATION_RE.finditer(raw))
    if not matches:
        return None
    total = timedelta()
    for match in matches:
        value = int(match.group("value"))
        unit = match.group("unit").lower()
        if unit.startswith("week"):
            total += timedelta(weeks=value)
        elif unit.startswith("day"):
            total += timedelta(days=value)
        elif unit.startswith("hour") or unit.startswith("hr"):
            total += timedelta(hours=value)
        elif unit.startswith("minute") or unit.startswith("min"):
            total += timedelta(minutes=value)
        elif unit.startswith("second") or unit.startswith("sec"):
            total += timedelta(seconds=value)
    return total if total.total_seconds() > 0 else None


def parse_day_phrase(raw, now_local):
    match = re.fullmatch(r"(today|tomorrow)(?:\s+(.+))?", raw.strip(), re.IGNORECASE)
    if not match:
        return None
    day_word = match.group(1).lower()
    clock_part = match.group(2)
    target_date = now_local.date()
    if day_word == "tomorrow":
        target_date = target_date + timedelta(days=1)
    if clock_part:
        clock = parse_clock(clock_part)
        return datetime.combine(target_date, clock, tzinfo=now_local.tzinfo)
    return datetime.combine(target_date, now_local.timetz().replace(tzinfo=None), tzinfo=now_local.tzinfo)


def parse_weekday_phrase(raw, now_local):
    match = re.fullmatch(r"next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+(.+))?", raw.strip(), re.IGNORECASE)
    if not match:
        return None

    weekday_name = match.group(1).lower()
    clock_part = match.group(2)
    target_weekday = WEEKDAY_INDEX[weekday_name]
    days_ahead = (target_weekday - now_local.weekday()) % 7
    if days_ahead == 0:
        days_ahead = 7

    target_date = now_local.date() + timedelta(days=days_ahead)
    if clock_part:
        clock = parse_clock(clock_part)
        return datetime.combine(target_date, clock, tzinfo=now_local.tzinfo)
    return datetime.combine(target_date, now_local.timetz().replace(tzinfo=None), tzinfo=now_local.tzinfo)


def reject_explicit_timezone(raw):
    tokens = raw.strip().split()
    if not tokens:
        return

    last_token = tokens[-1].lower().rstrip(",")
    if last_token in TIMEZONE_TOKENS or ("/" in last_token and last_token[0].isalpha()):
        raise ValueError(
            "Explicit timezone suffixes are not supported. Use machine time or set DEFER_TIMEZONE."
        )


def parse_time_expression(raw):
    tzinfo = local_tz()
    now_local = datetime.now(tzinfo)
    text = raw.strip()
    lowered = text.lower()

    if not text:
        raise ValueError("Time expression is empty")

    if lowered == "now":
        return now_local

    if lowered == "noon":
        return datetime.combine(now_local.date(), time(12, 0), tzinfo=tzinfo)

    if lowered == "midnight":
        return datetime.combine(now_local.date() + timedelta(days=1), time(0, 0), tzinfo=tzinfo)

    iso_value = parse_iso(text, tzinfo)
    if iso_value is not None:
        return iso_value

    reject_explicit_timezone(text)

    day_phrase = parse_day_phrase(text, now_local)
    if day_phrase is not None:
        return day_phrase

    weekday_phrase = parse_weekday_phrase(text, now_local)
    if weekday_phrase is not None:
        return weekday_phrase

    if lowered.startswith("+"):
        lowered = lowered[1:].strip()

    if lowered.startswith("in "):
        lowered = lowered[3:].strip()

    compact = parse_compact_duration(lowered)
    if compact is not None:
        return now_local + compact

    verbose = parse_verbose_duration(lowered)
    if verbose is not None:
        return now_local + verbose

    try:
        clock = parse_clock(text)
        return datetime.combine(now_local.date(), clock, tzinfo=tzinfo)
    except ValueError:
        pass

    raise ValueError(f"Unsupported time expression: {raw}")


def main():
    parser = argparse.ArgumentParser(description="Normalize defer skill time expressions.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    normalize_parser = subparsers.add_parser("normalize")
    normalize_parser.add_argument("expression")

    epoch_parser = subparsers.add_parser("epoch")
    epoch_parser.add_argument("expression")

    args = parser.parse_args()

    try:
        parsed = parse_time_expression(args.expression)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if args.command == "normalize":
        print(as_utc_iso(parsed))
        return 0

    print(int(parsed.timestamp()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
