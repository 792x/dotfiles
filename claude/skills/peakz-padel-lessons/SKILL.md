---
name: peakz-padel-lessons
description: Find Peakz Padel lessons and clinics (lesson packages, private lessons, clinics) at chosen locations, days and times, through Peakz's public API instead of their clunky calendar site. Use when the user asks about padel lessons, padellessen, clinics, a privéles or trainers at Peakz Padel, or wants available lesson slots in Utrecht or Amsterdam.
---

# Peakz Padel lessons

peakzpadel.nl is hard to search: the calendar pages 30 items at a time across
every location and has no time-of-day filter. Both booking pages read a public
Foys API, which needs no login, so query it directly.

## Quick run

```bash
python3 ~/.claude/skills/peakz-padel-lessons/scripts/peakz_lessons.py
```

Defaults match the user's standing preferences: adults, weekdays (ma–vr),
starting 17:00 or later, at **Vechtsebanen** and **Zeehaenkade** (Utrecht) and
**Kauwgomballenkwartier** and **Zuidoost** (Amsterdam). The user plays weekly
with a fixed group of four, so beginner-level offers ("Starterspakket", level
9/10-only clinics) are probably too easy. Show them, but say so.

It also lists **King of the Court** sessions at Vechtsebanen and Zeehaenkade on
any day and time, a social format the user wants tracked too.

Flags: `--from 18:00`, `--to 22:00`, `--days ma,di,wo,do`,
`--locations Zeehaenkade,Spoorzone`, `--kotc-locations …` (empty string skips
King of the Court), `--kotc-days za,zo`, `--json`, `--list-locations`, `--new`.
Location names are the short form (`Zuidoost`, not `Amsterdam - Zuidoost`).

## Daily check for new offers

`--new` prints only bookable items (free spots > 0) whose id an earlier `--new`
run has not recorded, then records everything it fetched. The state lives in
`~/.local/state/peakz-lessons/seen.json` (per machine), per kind (`lessons`,
`clinics`, `kotc`). A kind with no state yet is recorded as a baseline and not
reported, so adding a kind later doesn't flood the next report. When nothing is new it prints
`Nothing new.`

For a scheduled morning check: run with `--new`. If it prints `Nothing new.`,
end with one line saying so and no notification. Otherwise report the new items
as below and send one short notification, e.g. "Peakz: nieuwe clinic wo 21 okt 19:00 Zuidoost (2 vrij)".

If the user asks for something the script doesn't cover, call the endpoints
below with `curl` or Python.

## The API

Organisation id: `df82f4dd-fd87-4af5-9c2f-656fe1a44357` (`$ORG` below).

**Lessons** (lesson packages and single lessons; site page `/reserveren/lessons`)

- `GET https://api.foys.io/trainer-booking/public/api/v1/organisations/$ORG/lesson-packages?skipCount=0&maxResultCount=100&organisationId=$ORG`
  returns `{totalCount, items}`; page with `skipCount`. Fields used: `name`,
  `categoryName`, `startDate` (first lesson), `startTime`, `endTime`,
  `dayOfWeek` (English), `amountOfLessons` (weekly), `locationName`,
  `locationCity`, `price`, `trainerName`, `availableSlots`.
- Lookups under the same base: `lookup/locations`, `lookup/categories`,
  `lookup/trainers`, `lookup/levels`.
- Categories: 5 = Losse les (private lesson for one person or a group of up to 4),
  3/97/98/216/217/218 = Lespakket 5/4/8/7/6/3 weeks, 88/92/93/94 = Kids. Drop
  kids by category, and also by a "(… JAAR)" age range in `name`.

**Clinics and events** (site page `/reserveren/kalender`)

- `GET https://api.foys.io/foys/api/v2/pub/public-calendar?organisationId=$ORG&start=<ISO date>Z&calendarItemTypes[]=Event&skipCount=0&maxResultCount=200`
  returns every event at every location (thousands of rows, some years ahead).
  Items carry no category field, but the query takes `&categoryIds[]=302`
  (Academy), which returns only clinics plus the single lessons some locations
  post as events ("🎓 Losse les -Trainer …"). The script uses that filter.
  `start`/`end` are local time without an offset. Free spots =
  `maxAmountOfAttendances - countGoing` (where `countGoing` null = 0).
  `description` is HTML holding level, trainer and the exact price.
- Calendar categories (`/calendar/$ORG/categories`): 302 = Academy Clinics,
  3 = Jack's Hustle, 5 = King of the Court, 10 = Train with a Pro, 12 = Kids.
- Titles carry the Peakz rating: lower is stronger, 10 = beginner. "STA" =
  Starters (KNLTB 9–8). Jack's Hustle and Funky Friday are social play
  formats, not lessons. Mention them only if asked.
- King of the Court: you sign up per duo. `price` is per duo (the description
  gives the per-person price) and `maxAmountOfAttendances` counts duos. Category
  5 also holds ladies-only "Queen of the Court", and the mixed-couples edition
  is outside category 5, so the script matches titles on "King of the Court" or
  "KOTC". In Utrecht it runs Sunday 11:00–13:30 (INT at both locations, ADV at
  Vechtsebanen) plus the odd Saturday evening.

## Reporting

- Answer in the user's language (Dutch by default) with a table per kind:
  lessons, then clinics. Each row: date, weekday, time, location, title,
  trainer, price, free spots.
- Lesson `price` is for the whole booking, whether 1, 2, 3 or 4 players come
  (the lesson detail page says so). Divide by 4 for a full group's per-person cost.
- Clinic prices are per person.
- No evening private lessons listed? Suggest contacting the location directly,
  because trainers have time that isn't published.
- Give every row its direct booking link (the script's `url` field), so the user
  can open that lesson or clinic in one click:
  lesson `https://www.peakzpadel.nl/reserveren/lessons/packages/<id>`,
  clinic `https://www.peakzpadel.nl/reserveren/kalender-event?id=<id>`.

## If the API changes

Open https://www.peakzpadel.nl/reserveren/lessons in a browser and read the
`api.foys.io` requests in `performance.getEntriesByType('resource')` or the
network panel. The calendar page's first page is server-rendered, so click to
page 2 to trigger its API call. Decline non-essential cookies on the consent
banner.
