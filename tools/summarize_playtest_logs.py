#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable, Sequence


KNOWN_EVENTS = {
    "session_started", "session_finished", "profile_started",
    "tutorial_completed", "route_changed",
    "contract_started", "contract_finished", "training_completed",
    "loadout_changed", "forge_committed", "item_salvaged",
    "auto_rejected", "auto_unlocked", "early_game_completed",
    "prototype_debug_applied",
}
REAL_LOADOUT_ACTIONS = {"equip_item", "unequip_item"}


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize playtest JSONL logs.")
    parser.add_argument("inputs", nargs="+", help="JSONL files or directories")
    parser.add_argument("--output", metavar="PATH", help="write Markdown to PATH")
    return parser.parse_args(argv)


def collect_paths(inputs: Iterable[str]) -> list[Path]:
    found: set[Path] = set()
    for raw in inputs:
        path = Path(raw).expanduser().resolve()
        if not path.exists():
            raise ValueError("input does not exist: " + raw)
        if path.is_dir():
            found.update(item.resolve() for item in path.rglob("*.jsonl") if item.is_file())
        elif path.is_file():
            found.add(path)
        else:
            raise ValueError("input is neither file nor directory: " + raw)
    return sorted(found)


def finite(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    return None


def display(value: Any) -> str:
    numeric = finite(value)
    if numeric is not None:
        return str(int(numeric)) if numeric.is_integer() else format(numeric, ".3f").rstrip("0").rstrip(".")
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def msec(value: float) -> str:
    value = max(0.0, value)
    if value < 60_000:
        return format(value / 1000, ".3f") + "s"
    minutes, remainder = divmod(int(value), 60_000)
    return str(minutes) + "m " + format(remainder / 1000, ".3f") + "s"


def sec(value: float) -> str:
    return format(value, ".3f") + "s"


def counts(values: Counter[str]) -> str:
    return "; ".join(key + " x" + str(values[key]) for key in sorted(values)) or "-"


def delta(value: Any) -> str:
    numeric = finite(value)
    return "-" if numeric is None else format(numeric, "+.3f")


def optional(payload: dict[str, Any], key: str) -> str:
    return "not recorded" if payload.get(key) is None else display(payload[key])


def stats_row(label: str, values: list[float], formatter) -> str:
    ordered = sorted(values)
    return "| {} | {} | {} | {} | {} |".format(
        label, len(ordered), formatter(ordered[0]),
        formatter(statistics.median(ordered)), formatter(ordered[-1]),
    )


def read_events(paths: Sequence[Path]):
    events = []
    warnings = []
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            warnings.append((path, 1, "unreadable file", str(error)))
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            raw = line.strip()
            if not raw:
                warnings.append((path, line_number, "blank line", ""))
                continue
            try:
                value = json.loads(raw)
            except json.JSONDecodeError as error:
                warnings.append((path, line_number, "invalid JSON", str(error)))
                continue
            if not isinstance(value, dict):
                warnings.append((path, line_number, "JSON value is not an object", ""))
                continue
            event_id = value.get("event_id")
            session_id = value.get("session_id")
            if not isinstance(event_id, str) or not event_id:
                warnings.append((path, line_number, "missing event_id", ""))
                continue
            if not isinstance(session_id, str) or not session_id:
                warnings.append((path, line_number, "missing session_id", ""))
                continue
            if event_id not in KNOWN_EVENTS:
                warnings.append((path, line_number, "unknown event", event_id))
            context = value.get("context", {})
            payload = value.get("payload", {})
            if not isinstance(context, dict):
                warnings.append((path, line_number, "invalid context", "not an object"))
                context = {}
            if not isinstance(payload, dict):
                warnings.append((path, line_number, "invalid payload", "not an object"))
                payload = {}
            events.append({
                "event_id": event_id,
                "session_id": session_id,
                "sequence": value.get("sequence"),
                "time": finite(value.get("unix_msec")),
                "context": context,
                "payload": payload,
                "path": path,
                "line": line_number,
            })
    return events, warnings


def grouped_sessions(events):
    result = defaultdict(list)
    for event in events:
        result[event["session_id"]].append(event)
    sessions = []
    for session_id in sorted(result):
        records = result[session_id]
        if all(isinstance(item["sequence"], int) for item in records):
            records.sort(key=lambda item: (item["sequence"], item["path"].as_posix(), item["line"]))
        sessions.append((session_id, records))
    return sessions


def events_of(records, event_id):
    return [item for item in records if item["event_id"] == event_id]


def is_tradeoff(event):
    payload = event["payload"]
    previous = payload.get("previous_instance_id")
    next_id = payload.get("next_instance_id")
    return bool(previous) and bool(next_id) and previous != next_id


def contract_line(event):
    payload = event["payload"]
    details = [
        "outcome " + optional(payload, "outcome"),
        "mode " + optional(payload, "mode"),
        "rooms " + optional(payload, "rooms_completed") + "/" + optional(payload, "room_count"),
    ]
    elapsed = finite(payload.get("elapsed_seconds"))
    if elapsed is not None:
        details.append("elapsed " + sec(elapsed))
    if payload.get("failure_reason") is not None:
        details.append("failure " + display(payload["failure_reason"]))
    if payload.get("primary_bottleneck") is not None:
        details.append("bottleneck " + display(payload["primary_bottleneck"]))
    rooms = payload.get("rooms", [])
    if isinstance(rooms, list) and rooms:
        chain = []
        for room in rooms:
            if isinstance(room, dict):
                item = display(room.get("room_id", "unknown")) + ":" + display(room.get("outcome", "not recorded"))
                if room.get("failure_reason") is not None:
                    item += "(" + display(room["failure_reason"]) + ")"
                chain.append(item)
        if chain:
            details.append("room chain " + ", ".join(chain))
    return "- " + optional(payload, "contract_id") + ": " + "; ".join(details)


def loadout_line(event):
    payload = event["payload"]
    details = ["action " + optional(payload, "action"), "slot " + optional(payload, "slot")]
    if "previous_instance_id" in payload or "next_instance_id" in payload:
        details.append("item " + (payload.get("previous_instance_id") or "(empty)") + " -> " + (payload.get("next_instance_id") or "(empty)"))
    if "previous_build_fingerprint" in payload or "new_build_fingerprint" in payload:
        details.append("fingerprint " + optional(payload, "previous_build_fingerprint") + " -> " + optional(payload, "new_build_fingerprint"))
    if "growth_before" in payload or "growth_after" in payload:
        details.append("growth " + optional(payload, "growth_before") + " -> " + optional(payload, "growth_after"))
    gained = payload.get("interfaces_gained")
    lost = payload.get("interfaces_lost")
    if isinstance(gained, list) and gained:
        details.append("interfaces +" + display(gained))
    if isinstance(lost, list) and lost:
        details.append("interfaces -" + display(lost))
    changes = payload.get("parameter_deltas")
    if isinstance(changes, dict) and changes:
        rendered = [key + " " + delta(changes[key]) for key in sorted(changes)]
        if rendered:
            details.append("delta " + ", ".join(rendered))
    return "  - " + "; ".join(details) + " (" + str(event["path"]) + ":" + str(event["line"]) + ")"


def render_session(session_id, records):
    lines = ["## Session " + session_id, ""]
    lines.append("- Source: " + ", ".join(str(path) for path in sorted({item["path"] for item in records})))
    first_context = next((item["context"] for item in records if item["context"]), None)
    lines.append("- Context: " + (display(first_context) if first_context is not None else "not recorded"))
    finished = events_of(records, "session_finished")
    if finished:
        lines.append("- Status: finished; reason " + optional(finished[0]["payload"], "reason"))
    else:
        last = records[-1]
        lines.append("- Status: truncated; last event " + str(last["path"]) + ":" + str(last["line"]))
    times = [item["time"] for item in records if item["time"] is not None]
    lines.append("- Recorded event span: " + (msec(max(times) - min(times)) if times else "not recorded"))
    lines.append("- Valid parsed events: " + str(len(records)))

    routes = events_of(records, "route_changed")
    if routes:
        rendered = []
        for event in routes:
            payload = event["payload"]
            dwell = finite(payload.get("previous_dwell_msec"))
            rendered.append(
                display(payload.get("from", "not recorded")) + " -> " +
                display(payload.get("to", "not recorded")) + " (previous dwell " +
                (msec(dwell) if dwell is not None else "not recorded") + ")"
            )
        lines.append("- Routes: " + "; ".join(rendered))

    started = events_of(records, "contract_started")
    contracts = events_of(records, "contract_finished")
    if started or contracts:
        lines.extend(["", "### Contracts"])
        ids = sorted({str(item["payload"].get("contract_id", "not recorded")) for item in started + contracts})
        for contract_id in ids:
            starts = sum(str(item["payload"].get("contract_id")) == contract_id for item in started)
            finishes = [item for item in contracts if str(item["payload"].get("contract_id")) == contract_id]
            outcomes = Counter(str(item["payload"].get("outcome", "not recorded")) for item in finishes)
            lines.append("- " + contract_id + ": started " + str(starts) + ", finished " + str(len(finishes)) + "; outcomes " + counts(outcomes))
        lines.extend(contract_line(item) for item in contracts)

    training = events_of(records, "training_completed")
    if training:
        last = training[-1]["payload"]
        lines.extend(["", "### Training"])
        lines.append("- Count: " + str(len(training)))
        lines.append("- Last classification: " + optional(last, "growth_classification"))
        lines.append("- Last p/R: " + optional(last, "p") + " / " + optional(last, "R"))

    loadouts = [item for item in events_of(records, "loadout_changed") if item["payload"].get("action") in REAL_LOADOUT_ACTIONS]
    if loadouts:
        action_counts = Counter(str(item["payload"].get("action")) for item in loadouts)
        tradeoffs = sum(is_tradeoff(item) for item in loadouts)
        lines.extend(["", "### Real item loadout changes"])
        lines.append("- Count: " + str(len(loadouts)) + " (" + counts(action_counts) + "); replacement tradeoffs " + str(tradeoffs))
        lines.extend(loadout_line(item) for item in loadouts)

    forged = events_of(records, "forge_committed")
    salvaged = events_of(records, "item_salvaged")
    if forged or salvaged:
        lines.extend(["", "### Forge and salvage"])
        for item in forged:
            payload = item["payload"]
            lines.append("- Forge " + optional(payload, "instance_id") + ": track " + optional(payload, "track") + ", family " + optional(payload, "family_id") + ", tier " + optional(payload, "tier") + ", cost " + optional(payload, "cost"))
        for item in salvaged:
            payload = item["payload"]
            lines.append("- Salvage " + optional(payload, "instance_id") + ": track " + optional(payload, "track") + ", amount " + optional(payload, "amount"))

    profiles = events_of(records, "profile_started")
    tutorials = events_of(records, "tutorial_completed")
    rejections = events_of(records, "auto_rejected")
    unlocks = events_of(records, "auto_unlocked")
    graduated = events_of(records, "early_game_completed")
    if profiles or tutorials or rejections or unlocks or graduated:
        lines.extend(["", "### Milestones"])
        for item in profiles:
            lines.append("- New profile: class " + optional(item["payload"], "initial_class"))
        for item in tutorials:
            lines.append("- Tutorial completed: class " + optional(item["payload"], "initial_class"))
        for item in rejections:
            payload = item["payload"]
            lines.append("- Auto rejected: contract " + optional(payload, "contract_id") + ", reason " + optional(payload, "reason"))
        for item in unlocks:
            elapsed = finite(item["payload"].get("profile_elapsed_msec"))
            lines.append("- Boss first kill / Auto unlock: profile time " + (msec(elapsed) if elapsed is not None else "not recorded"))
        for item in graduated:
            elapsed = finite(item["payload"].get("profile_elapsed_msec"))
            lines.append("- Early-game graduation: profile time " + (msec(elapsed) if elapsed is not None else "not recorded"))
    lines.append("")
    return lines


def render(paths, events, warnings):
    sessions = grouped_sessions(events)
    finished = [records for _, records in sessions if events_of(records, "session_finished")]
    truncated = [records for _, records in sessions if not events_of(records, "session_finished")]
    loadouts = [item for item in events if item["event_id"] == "loadout_changed" and item["payload"].get("action") in REAL_LOADOUT_ACTIONS]

    lines = ["# Make It Big Playtest Log Summary", "", "## Overview", ""]
    lines.append("- Input JSONL files: " + str(len(paths)))
    lines.append("- Session identity: top-level event session_id (envelope source: src/game/playtest_log.gd)")
    lines.append("- Valid parsed events: " + str(len(events)))
    lines.append("- Sessions: " + str(len(sessions)) + "; finished " + str(len(finished)) + "; truncated " + str(len(truncated)))
    lines.append("- Real item loadout changes: " + str(len(loadouts)) + "; replacement tradeoffs " + str(sum(is_tradeoff(item) for item in loadouts)))
    lines.append("- Training events: " + str(sum(item["event_id"] == "training_completed" for item in events)))
    lines.append("- Forge commits: " + str(sum(item["event_id"] == "forge_committed" for item in events)))
    lines.append("- Item salvages: " + str(sum(item["event_id"] == "item_salvaged" for item in events)))
    lines.append("- Auto rejections: " + str(sum(item["event_id"] == "auto_rejected" for item in events)))
    lines.append("")

    spans = []
    finished_spans = []
    for _, records in sessions:
        times = [item["time"] for item in records if item["time"] is not None]
        if times:
            spans.append(max(times) - min(times))
            if events_of(records, "session_finished"):
                finished_spans.append(max(times) - min(times))
    contract_times = []
    boss_times = []
    auto_times = []
    unlock_times = []
    graduation_times = []
    for item in events:
        if item["event_id"] == "contract_finished":
            elapsed = finite(item["payload"].get("elapsed_seconds"))
            if elapsed is not None:
                contract_times.append(elapsed)
                contract_id = str(item["payload"].get("contract_id"))
                if contract_id == "threshold_colossus":
                    boss_times.append(elapsed)
                elif contract_id == "auto_certification":
                    auto_times.append(elapsed)
        elif item["event_id"] == "auto_unlocked":
            value = finite(item["payload"].get("profile_elapsed_msec"))
            if value is not None:
                unlock_times.append(value)
        elif item["event_id"] == "early_game_completed":
            value = finite(item["payload"].get("profile_elapsed_msec"))
            if value is not None:
                graduation_times.append(value)

    lines.extend(["## Transparent numeric summary", "", "| Metric | Samples | Min | Median | Max |", "|---|---:|---:|---:|---:|"])
    if spans:
        lines.append(stats_row("Session event span (all)", spans, msec))
    if finished_spans:
        lines.append(stats_row("Session event span (finished)", finished_spans, msec))
    if contract_times:
        lines.append(stats_row("Contract elapsed", contract_times, sec))
    if boss_times:
        lines.append(stats_row("Boss contract elapsed", boss_times, sec))
    if auto_times:
        lines.append(stats_row("Auto certification elapsed", auto_times, sec))
    if unlock_times:
        lines.append(stats_row("Auto unlock profile time", unlock_times, msec))
    if graduation_times:
        lines.append(stats_row("Graduation profile time", graduation_times, msec))
    lines.extend(["", "Only min/median/max descriptive counts are calculated; no statistical significance is inferred.", ""])

    dwell_by_route = defaultdict(list)
    outcomes = defaultdict(Counter)
    failures = Counter()
    bottlenecks = Counter()
    auto_rejections = Counter()
    for item in events:
        if item["event_id"] == "route_changed":
            value = finite(item["payload"].get("previous_dwell_msec"))
            if value is not None:
                dwell_by_route[str(item["payload"].get("from", "not recorded"))].append(value)
        elif item["event_id"] == "contract_finished":
            payload = item["payload"]
            contract_id = str(payload.get("contract_id", "not recorded"))
            outcomes[contract_id][str(payload.get("outcome", "not recorded"))] += 1
            if payload.get("failure_reason") is not None:
                failures[str(payload["failure_reason"])] += 1
            if payload.get("primary_bottleneck") is not None:
                bottlenecks[str(payload["primary_bottleneck"])] += 1
        elif item["event_id"] == "auto_rejected":
            auto_rejections[str(item["payload"].get("reason", "not recorded"))] += 1
    if dwell_by_route:
        lines.extend(["### Route dwell", "", "| Route | Samples | Total | Min | Median | Max |", "|---|---:|---:|---:|---:|---:|"])
        for route in sorted(dwell_by_route):
            values = sorted(dwell_by_route[route])
            lines.append("| " + route + " | " + str(len(values)) + " | " + msec(sum(values)) + " | " + msec(values[0]) + " | " + msec(statistics.median(values)) + " | " + msec(values[-1]) + " |")
        lines.append("")
    if outcomes:
        lines.extend(["## Contract outcomes", "", "| Contract | Finished | Outcomes |", "|---|---:|---|"])
        for contract_id in sorted(outcomes):
            lines.append("| " + contract_id + " | " + str(sum(outcomes[contract_id].values())) + " | " + counts(outcomes[contract_id]) + " |")
        lines.append("")
    if failures or bottlenecks:
        lines.extend(["## Failure observations", ""])
        if failures:
            lines.append("- failure_reason: " + counts(failures))
        if bottlenecks:
            lines.append("- primary_bottleneck: " + counts(bottlenecks))
        lines.append("")
    if auto_rejections:
        lines.extend(["## Auto rejections", "", "- Reasons: " + counts(auto_rejections), ""])

    for session_id, records in sessions:
        lines.extend(render_session(session_id, records))

    report_warnings = list(warnings)
    for records in truncated:
        last = records[-1]
        report_warnings.append((last["path"], last["line"], "truncated session", ""))
    lines.extend(["## Warnings", ""])
    if report_warnings:
        for path, line, category, detail in sorted(report_warnings, key=lambda item: (item[0].as_posix(), item[1], item[2], item[3])):
            suffix = ": " + detail if detail else ""
            lines.append("- " + str(path) + ":" + str(line) + ": " + category + suffix)
    else:
        lines.append("- None")
    lines.append("")
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        paths = collect_paths(args.inputs)
        if not paths:
            raise ValueError("no *.jsonl files found")
        events, warnings = read_events(paths)
        report = render(paths, events, warnings)
    except ValueError as error:
        print("error: " + str(error), file=sys.stderr)
        return 2
    if args.output:
        try:
            Path(args.output).expanduser().resolve().write_text(report, encoding="utf-8")
        except OSError as error:
            print("error: cannot write output: " + str(error), file=sys.stderr)
            return 2
    else:
        print(report, end="")
    return 1 if not events else 0


if __name__ == "__main__":
    raise SystemExit(main())
