#!/usr/bin/env python3
"""List adult Peakz Padel lessons, clinics and King of the Court sessions.

Lessons and clinics are filtered by --locations/--days, King of the Court
sessions by --kotc-locations/--kotc-days. For all three, --from/--to bound the
start time on weekdays only; weekend sessions count at any time. Clinics on
overhead shots (bandeja, vibora, smash, ...) are marked, and --overhead keeps
only those.

Reads the public Foys API behind peakzpadel.nl (no login, no cookies).

  peakz_lessons.py                                   # defaults below
  peakz_lessons.py --from 18:00
  peakz_lessons.py --locations Zeehaenkade,Vechtsebanen --days ma,di,wo,do
  peakz_lessons.py --list-locations
  peakz_lessons.py --json
  peakz_lessons.py --kotc-days za,zo
  peakz_lessons.py --overhead     # only clinics on overhead shots
  peakz_lessons.py --new          # only what appeared since the last --new run
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

ORG = "df82f4dd-fd87-4af5-9c2f-656fe1a44357"
LESSONS_API = f"https://api.foys.io/trainer-booking/public/api/v1/organisations/{ORG}"
CALENDAR_API = "https://api.foys.io/foys/api/v2/pub"

DEFAULT_LOCATIONS = "Vechtsebanen,Zeehaenkade,Kauwgomballenkwartier,Zuidoost"
DEFAULT_KOTC_LOCATIONS = "Vechtsebanen,Zeehaenkade,Zuidoost,Kauwgomballenkwartier"
# Category 5 also holds ladies-only "Queen of the Court", and the mixed-couples
# edition sits outside it, so match on the title instead.
KOTC_TITLE = re.compile(r"king of the court|kotc", re.I)
OVERHEAD_TITLE = re.compile(
    r"bandeja|v[ií]bora|smash|rulo|gancho|bajada|overhead|remate|por ?(3|4|tres|cuatro)|\bx ?[34]\b", re.I)


def in_window(day, hhmm, days, from_time, to_time):
    """Weekdays need a start within --from/--to; weekends count at any time."""
    if DAYS[day] not in days:
        return False
    return day >= 5 or from_time <= hhmm < to_time
DAYS = ["ma", "di", "wo", "do", "vr", "za", "zo"]
EN_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

BOOK_LESSONS = "https://www.peakzpadel.nl/reserveren/lessons"
BOOK_CLINICS = "https://www.peakzpadel.nl/reserveren/kalender?categoryIds=302"
LESSON_URL = "https://www.peakzpadel.nl/reserveren/lessons/packages/{id}"
CLINIC_URL = "https://www.peakzpadel.nl/reserveren/kalender-event?id={id}"
ACADEMY_CATEGORY = 302  # clinics, plus single lessons some locations post as events
STATE_FILE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "peakz-lessons/seen.json"


def get(url, attempts=4):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for i in range(attempts):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            if i == attempts - 1:
                raise
            time.sleep(2 ** i)  # the API drops a connection now and then


def paged(url_fmt, page):
    items, skip = [], 0
    while True:
        data = get(url_fmt.format(skip=skip, n=page))
        batch = data.get("items", [])
        items += batch
        skip += len(batch)
        if not batch or skip >= data.get("totalCount", 0):
            return items


def lessons(locs, days, from_time, to_time):
    rows = paged(
        f"{LESSONS_API}/lesson-packages?skipCount={{skip}}&maxResultCount={{n}}&organisationId={ORG}",
        page=100,
    )
    out = []
    for x in rows:
        if x["locationName"] not in locs:
            continue
        if x["categoryName"].startswith("Kids") or "jaar)" in x["name"].lower():
            continue
        if not in_window(EN_DAYS.index(x["dayOfWeek"]), x["startTime"][:5], days, from_time, to_time):
            continue
        out.append({
            "kind": "lesson",
            "date": x["startDate"][:10],
            "day": DAYS[EN_DAYS.index(x["dayOfWeek"])],
            "start": x["startTime"][:5],
            "end": x["endTime"][:5],
            "location": x["locationName"],
            "title": x["name"],
            "lessons": x["amountOfLessons"],
            "price": x["price"],
            "trainer": x["trainerName"],
            "free": x["availableSlots"],
            "id": x["id"],
            "url": LESSON_URL.format(id=x["id"]),
        })
    return sorted(out, key=lambda r: (r["date"], r["start"]))


def clinics(locs, days, from_time, to_time, overhead_only=False):
    today = datetime.now().strftime("%Y-%m-%dT00:00:00.000Z")
    rows = paged(
        f"{CALENDAR_API}/public-calendar?organisationId={ORG}&start={today}"
        f"&calendarItemTypes[]=Event&categoryIds[]={ACADEMY_CATEGORY}"
        "&skipCount={skip}&maxResultCount={n}",
        page=200,
    )
    out = []
    for e in rows:
        loc = next((l["name"] for l in e["locations"] if l["name"] in locs), None)
        if not loc:
            continue
        start = datetime.fromisoformat(e["start"])
        if not in_window(start.weekday(), start.strftime("%H:%M"), days, from_time, to_time):
            continue
        overhead = bool(OVERHEAD_TITLE.search(e["title"]))
        if overhead_only and not overhead:
            continue
        cap = e.get("maxAmountOfAttendances") or 0
        out.append({
            "kind": "clinic",
            "overhead": overhead,
            "date": start.strftime("%Y-%m-%d"),
            "day": DAYS[start.weekday()],
            "start": start.strftime("%H:%M"),
            "end": e["end"][11:16],
            "location": loc,
            "title": e["title"],
            "price": e["price"],
            "free": cap - (e.get("countGoing") or 0),
            "id": e["id"],
            "url": CLINIC_URL.format(id=e["id"]),
        })
    return sorted(out, key=lambda r: (r["date"], r["start"]))


def kotc(locs, days, from_time, to_time):
    today = datetime.now().strftime("%Y-%m-%dT00:00:00.000Z")
    rows = paged(
        f"{CALENDAR_API}/public-calendar?organisationId={ORG}&start={today}"
        "&calendarItemTypes[]=Event&skipCount={skip}&maxResultCount={n}",
        page=200,
    )
    out = []
    for e in rows:
        loc = next((l["name"] for l in e["locations"] if l["name"] in locs), None)
        if not loc or not KOTC_TITLE.search(e["title"]):
            continue
        start = datetime.fromisoformat(e["start"])
        if not in_window(start.weekday(), start.strftime("%H:%M"), days, from_time, to_time):
            continue
        cap = e.get("maxAmountOfAttendances") or 0
        # Hustle editions take individual sign-ups; the rest are booked per duo.
        unit = "person" if "hustle" in e["title"].lower() else "duo"
        out.append({
            "kind": "kotc",
            "date": start.strftime("%Y-%m-%d"),
            "day": DAYS[start.weekday()],
            "start": start.strftime("%H:%M"),
            "end": e["end"][11:16],
            "location": loc,
            "title": e["title"],
            "unit": unit,
            "price": e["price"],  # per unit
            "free": cap - (e.get("countGoing") or 0),  # in units
            "id": e["id"],
            "url": CLINIC_URL.format(id=e["id"]),
        })
    return sorted(out, key=lambda r: (r["date"], r["start"]))


def only_new(results):
    """Keep bookable items no earlier --new run recorded, then record everything.

    State is kept per kind, so a kind the state has never seen (the first run,
    or a kind added later) is recorded as a baseline instead of reported.
    """
    state = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}
    if isinstance(state, list):  # before per-kind state, ids of lessons and clinics
        state = {"lessons": state, "clinics": state}
    baselined = []
    for kind, rows in results.items():
        current = {str(r["id"]) for r in rows}
        if kind not in state:
            baselined.append(f"{kind} ({len(current)})")
            results[kind] = []
        else:
            seen = set(state[kind])
            results[kind] = [r for r in rows if str(r["id"]) not in seen and r["free"] > 0]
            current |= seen
        state[kind] = sorted(current)
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state))
    return baselined


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--locations", default=DEFAULT_LOCATIONS, help=f"comma-separated (default: {DEFAULT_LOCATIONS})")
    p.add_argument("--days", default=",".join(DAYS), help="comma-separated ma..zo (default: all)")
    p.add_argument("--from", dest="from_time", default="17:00", help="earliest weekday start, HH:MM (default 17:00)")
    p.add_argument("--to", dest="to_time", default="24:00", help="latest weekday start, exclusive, HH:MM")
    p.add_argument("--overhead", action="store_true", help="only clinics on overhead shots (bandeja, vibora, smash, ...)")
    p.add_argument("--kotc-locations", default=DEFAULT_KOTC_LOCATIONS,
                   help=f"King of the Court locations (default: {DEFAULT_KOTC_LOCATIONS}); empty to skip")
    p.add_argument("--kotc-days", default=",".join(DAYS), help="King of the Court days (default: all)")
    p.add_argument("--json", action="store_true", help="print JSON instead of a table")
    p.add_argument("--list-locations", action="store_true", help="print all Peakz locations and exit")
    p.add_argument("--new", action="store_true",
                   help=f"show only bookable items not seen by an earlier --new run (state: {STATE_FILE})")
    a = p.parse_args()

    if a.list_locations:
        for l in get(f"{LESSONS_API}/lookup/locations"):
            print(l["name"])
        return

    split = lambda v: {s.strip() for s in v.split(",") if s.strip()}
    locs, days = split(a.locations), {d.lower() for d in split(a.days)}
    kotc_locs, kotc_days = split(a.kotc_locations), {d.lower() for d in split(a.kotc_days)}
    results = {
        "lessons": lessons(locs, days, a.from_time, a.to_time),
        "clinics": clinics(locs, days, a.from_time, a.to_time, a.overhead),
        "kotc": kotc(kotc_locs, kotc_days, a.from_time, a.to_time) if kotc_locs else [],
    }

    if a.new:
        baselined = only_new(results)
        if baselined:
            print(f"Recorded a baseline for: {', '.join(baselined)}. Those are reported from the next --new run on.")
        if not any(results.values()) and not a.json:
            print("Nothing new.")
            return

    if a.json:
        json.dump(results, sys.stdout, ensure_ascii=False, indent=2)
        print()
        return

    status = lambda r: "FULL" if r["free"] <= 0 else f"{r['free']} free"
    print(f"\nLESSONS  ({', '.join(sorted(locs))}; {','.join(d for d in DAYS if d in days)}; weekdays {a.from_time}-{a.to_time}, weekends all day)\n")
    for r in results["lessons"]:
        print(f"{r['date']} {r['day']} {r['start']}-{r['end']}  {r['location']:<22} {r['title']:<28} "
              f"{r['lessons']}x  €{r['price']:.0f}  {r['trainer'] or '-'}  ({r['free']} free)\n    {r['url']}")
    print("\nCLINICS  (^ = overhead shot)\n")
    for r in results["clinics"]:
        print(f"{'^' if r['overhead'] else ' '} {r['date']} {r['day']} {r['start']}-{r['end']}  {r['location']:<22} "
              f"{r['title']:<42} €{r['price']:.2f}  {status(r)}\n    {r['url']}")
    if kotc_locs:
        print(f"\nKING OF THE COURT  ({', '.join(sorted(kotc_locs))}; {','.join(d for d in DAYS if d in kotc_days)}; weekdays {a.from_time}-{a.to_time}, weekends all day)\n")
        for r in results["kotc"]:
            print(f"{r['date']} {r['day']} {r['start']}-{r['end']}  {r['location']:<14} {r['title']:<48} "
                  f"€{r['price']:.0f}/{r['unit']}  {status(r)}\n    {r['url']}")
    print(f"\nBook lessons: {BOOK_LESSONS}\nBook clinics: {BOOK_CLINICS}\n")


if __name__ == "__main__":
    main()
