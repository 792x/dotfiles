#!/usr/bin/env python3
"""List adult Peakz Padel lessons and clinics, filtered by location, day and time.

Reads the public Foys API behind peakzpadel.nl (no login, no cookies).

  peakz_lessons.py                                   # defaults below
  peakz_lessons.py --from 18:00
  peakz_lessons.py --locations Zeehaenkade,Vechtsebanen --days ma,di,wo,do
  peakz_lessons.py --list-locations
  peakz_lessons.py --json
"""
import argparse
import json
import sys
import urllib.request
from datetime import datetime

ORG = "df82f4dd-fd87-4af5-9c2f-656fe1a44357"
LESSONS_API = f"https://api.foys.io/trainer-booking/public/api/v1/organisations/{ORG}"
CALENDAR_API = "https://api.foys.io/foys/api/v2/pub"

DEFAULT_LOCATIONS = "Vechtsebanen,Zeehaenkade,Kauwgomballenkwartier,Zuidoost"
DAYS = ["ma", "di", "wo", "do", "vr", "za", "zo"]
EN_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

BOOK_LESSONS = "https://www.peakzpadel.nl/reserveren/lessons"
BOOK_CLINICS = "https://www.peakzpadel.nl/reserveren/kalender?categoryIds=302"
LESSON_URL = "https://www.peakzpadel.nl/reserveren/lessons/packages/{id}"
CLINIC_URL = "https://www.peakzpadel.nl/reserveren/kalender-event?id={id}"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


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
        if DAYS[EN_DAYS.index(x["dayOfWeek"])] not in days:
            continue
        if x["categoryName"].startswith("Kids") or "jaar)" in x["name"].lower():
            continue
        if not from_time <= x["startTime"][:5] < to_time:
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


def clinics(locs, days, from_time, to_time):
    today = datetime.now().strftime("%Y-%m-%dT00:00:00.000Z")
    rows = paged(
        f"{CALENDAR_API}/public-calendar?organisationId={ORG}&start={today}"
        "&calendarItemTypes[]=Event&skipCount={skip}&maxResultCount={n}",
        page=200,
    )
    out = []
    for e in rows:
        loc = next((l["name"] for l in e["locations"] if l["name"] in locs), None)
        if not loc or "clinic" not in e["title"].lower():
            continue
        start = datetime.fromisoformat(e["start"])
        if DAYS[start.weekday()] not in days:
            continue
        if not from_time <= start.strftime("%H:%M") < to_time:
            continue
        cap = e.get("maxAmountOfAttendances") or 0
        out.append({
            "kind": "clinic",
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


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--locations", default=DEFAULT_LOCATIONS, help=f"comma-separated (default: {DEFAULT_LOCATIONS})")
    p.add_argument("--days", default="ma,di,wo,do,vr", help="comma-separated ma..zo (default: ma,di,wo,do,vr)")
    p.add_argument("--from", dest="from_time", default="17:00", help="earliest start, HH:MM (default 17:00)")
    p.add_argument("--to", dest="to_time", default="24:00", help="latest start, exclusive, HH:MM")
    p.add_argument("--json", action="store_true", help="print JSON instead of a table")
    p.add_argument("--list-locations", action="store_true", help="print all Peakz locations and exit")
    a = p.parse_args()

    if a.list_locations:
        for l in get(f"{LESSONS_API}/lookup/locations"):
            print(l["name"])
        return

    locs = {s.strip() for s in a.locations.split(",") if s.strip()}
    days = {s.strip().lower() for s in a.days.split(",") if s.strip()}
    les = lessons(locs, days, a.from_time, a.to_time)
    cli = clinics(locs, days, a.from_time, a.to_time)

    if a.json:
        json.dump({"lessons": les, "clinics": cli}, sys.stdout, ensure_ascii=False, indent=2)
        print()
        return

    print(f"\nLESSONS  ({', '.join(sorted(locs))}; {','.join(DAYS[i] for i in range(7) if DAYS[i] in days)}; {a.from_time}-{a.to_time})\n")
    for r in les:
        print(f"{r['date']} {r['day']} {r['start']}-{r['end']}  {r['location']:<22} {r['title']:<28} "
              f"{r['lessons']}x  €{r['price']:.0f}  {r['trainer'] or '-'}  ({r['free']} free)\n    {r['url']}")
    print("\nCLINICS\n")
    for r in cli:
        print(f"{r['date']} {r['day']} {r['start']}-{r['end']}  {r['location']:<22} {r['title']:<42} "
              f"€{r['price']:.2f}  {'FULL' if r['free'] <= 0 else str(r['free']) + ' free'}\n    {r['url']}")
    print(f"\nBook lessons: {BOOK_LESSONS}\nBook clinics: {BOOK_CLINICS}\n")


if __name__ == "__main__":
    main()
