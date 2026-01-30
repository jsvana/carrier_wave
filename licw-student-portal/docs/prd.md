# LICW Student Portal - Product Requirements Document

## Overview

A student-facing portal for Long Island CW Club members to discover classes, track progress, find forums, and access recordings—replacing the current fragmented experience across Discord, Groups.io, iCal, emails, and Dropbox.

## Problem Statement

LICW members currently must:
- Hunt through Groups.io posts to find forum schedules and topics
- Manually cross-reference iCal with their interests to find relevant classes
- Navigate a disliked Dropbox interface to watch recordings
- Rely on Discord or email for class recommendations and schedule changes

This fragmentation is especially painful for the club's older-skewing membership (primarily retirees, ranging from teens to 80s). Members miss classes they'd enjoy, don't know which forums cover topics they care about, and struggle to track their progression through the curriculum.

## Users

Two overlapping personas:

1. **Students** - Taking structured classes through the carousel curriculum (BC1-3 → INT1-3 → ADV1-3)
2. **Forum Members** - Attending weekly topic-based forums (Antenna, Portable Operations, etc.)

Most active students are also forum attendees. The portal serves both needs in a unified experience.

### User Identification
- Login via callsign
- Email addresses on file
- Join date known
- Skill level inferred from attendance patterns

## Curriculum Context

LICW uses a carousel model with no fixed entry point:
- **Beginners Carousel (BC1, BC2, BC3)** - Character learning via Koch method at 12 WPM
- **Intermediate (INT1, INT2, INT3)** - Fluency and conversational head copy
- **Advanced (ADV1, ADV2, ADV3)** - High-speed proficiency (QRQ)

Students self-select when to progress. Multiple sessions of each lesson run weekly, allowing flexible attendance.

**Forums** (5-10 total) meet weekly, are open to all skill levels, and cover topics like antennas, portable operations, vintage gear, etc. Moderators now enter weekly topics into the scheduling system by Sunday 3pm ET.

## Design Principles

1. **Show what matters, hide what doesn't** - No dashboards full of charts. Surface actionable information based on the individual's attendance and interests.

2. **One place, not five** - The portal replaces checking multiple platforms. If it's not in the portal, members shouldn't need to look elsewhere.

3. **Gentle guidance, not gatekeeping** - Suggest progression and surface opportunities without being prescriptive. Students choose their own pace.

4. **Respect the audience** - Clean, readable interface. No tiny fonts, no information overload, no assumptions about technical savvy.

## MVP Features

### 1. My Schedule
**The primary view. What's happening that I care about?**

- Shows upcoming classes and forums based on:
  - Classes I've previously attended (inferred interests)
  - My current curriculum level (inferred from attendance)
  - Forums I've attended before
- Each item shows: day, time (in user's timezone), class/forum name, this week's topic (for forums), Zoom room
- Simple "Add to Calendar" action for individual sessions
- Filter/toggle: Classes | Forums | Both

**What it replaces:** Manually scanning iCal, Groups.io forum announcements

### 2. My Progress
**Where am I in the curriculum?**

For Beginners Carousel students:
- Characters learned vs. characters remaining (inferred from lessons attended)
- Visual progress indicator (not percentage—something like "You've covered 18 of 26 characters")
- Sessions attended in current carousel
- Subtle suggestion when attendance patterns indicate readiness to advance (not prescriptive)

For Intermediate/Advanced:
- Sessions attended at current level
- Topics/skills covered based on attendance

**What it replaces:** No current equivalent—students track this mentally or not at all

### 3. Forums This Week
**What forums are happening and what are they about?**

- List of all forums with this week's topic (pulled from moderator entries)
- Meeting time and Zoom room
- "I'm interested" toggle to add to My Schedule
- Indicator if user has attended before

**What it replaces:** Groups.io announcements, Discord posts

### 4. Recordings
**Watch past classes and forums.**

- Organized by: Curriculum level (BC/INT/ADV) and Forums
- Sorted chronologically within each category (newest first)
- Search/filter by title
- "Featured" section for standout recordings (curated manually by admins)
- Clear titles with date and topic

**What it replaces:** Dropbox folder diving

### 5. Class Finder
**Explore classes outside my current track.**

- Browse all class types by level
- See weekly schedule for any class
- "This might interest you" recommendations based on:
  - What similar members attend (collaborative filtering)
  - Natural progressions (BC3 → INT1)
  - Complementary forums based on class attendance

**What it replaces:** Asking in Discord, stumbling upon things

## Information Architecture

```
Home (My Schedule - default view)
├── My Progress
├── Forums
│   └── [Forum Detail] - schedule, topics, recordings
├── Recordings
│   ├── Beginners
│   ├── Intermediate
│   ├── Advanced
│   ├── Forums
│   └── Featured
└── Explore Classes
    ├── By Level
    └── Recommendations
```

## Technical Context

- **Platform:** Laravel web app (existing)
- **Database:** Shared with admin.longislandcwclub.org
- **Authentication:** Callsign-based login (existing member database)
- **Existing student-facing feature:** Attendance history list
- **Data available:** Class schedules, attendance records, forum topics (entered weekly), recordings (platform TBD, currently Dropbox)

### Key Data Inferences

The portal will infer from attendance data:
1. **Current level** - Highest level class recently attended
2. **Interests** - Forums and supplemental classes attended
3. **Characters learned** - Mapped from BC lesson attendance
4. **Progression readiness** - Attendance count thresholds (to be defined)

## Success Metrics

| Metric | Measurement |
|--------|-------------|
| Forum attendance | Compare before/after portal launch |
| Class attendance | Compare before/after, especially for recommended classes |
| Progression rate | Students moving BC → INT → ADV |
| Member satisfaction | Qualitative survey feedback |

## Out of Scope for MVP

- Mobile native app (web responsive is sufficient)
- Real-time notifications/reminders (rely on existing email for now)
- Social features (profiles, messaging)
- Instructor-facing features (admin portal handles this)
- Recording upload/management (admin function)
- Integration with Discord or Groups.io (portal replaces, doesn't integrate)

## Open Questions

1. **Recording platform** - Where will recordings be hosted post-Dropbox migration? Affects embed/link approach.

2. **Progression thresholds** - What attendance counts suggest readiness to advance? Needs instructor input.

3. **Character-to-lesson mapping** - Need definitive map of which BC lessons teach which characters.

4. **Timezone handling** - Store user timezone preference, or detect from browser?

5. **"Interested" persistence** - If a user marks a forum as interesting, does that persist forever or reset periodically?

## Appendix: Current Pain Points (from leadership)

> "Dropbox is universally disliked"
> "Viewing recordings on Dropbox is not a positive experience"
> "There is too much Groups.io traffic"
> "Members need greater visibility into Forum schedules - and the topics covered each week"

The portal directly addresses all four.
