# LICW Discovery App - Product Requirements Document

**Version:** 1.0
**Date:** January 27, 2026
**Status:** Draft

---

## Executive Summary

The LICW Discovery App centralizes the Long Island CW Club's scattered resources into a single, accessible application. With 6,000+ members spanning 63 countries and age demographics from teens to octogenarians, the app prioritizes discoverability, simplicity, and accessibility above all else.

**Core Problem:** LICW content lives across multiple platforms (website, Dropbox, Groups.io, Zoom, Buzzsprout, calendar systems), making it difficult for members—especially less tech-savvy ones—to find what they need.

**Solution:** A unified discovery hub that surfaces the right content at the right time with minimal friction.

---

## Design Principles

### 1. Discoverability First
- Content should find the user, not the other way around
- Surface relevant items based on context (upcoming classes, new content, member's skill level)
- Search must be prominent, fast, and forgiving of typos

### 2. Clarity Over Completeness
- Show less, explain more
- Large touch targets (minimum 44pt)
- High contrast, readable typography
- Progressive disclosure—hide complexity until needed

### 3. Accessibility Non-Negotiables
- WCAG 2.1 AA compliance minimum
- VoiceOver/TalkBack full support
- Dynamic Type support (iOS) / Font scaling (Android)
- No information conveyed by color alone
- Minimum 4.5:1 contrast ratios

### 4. Offline-Capable
- Core content (calendar, newsletters) cached for offline access
- Clear indicators when viewing cached vs. live content
- Graceful degradation on poor connections

---

## Target Audience

| Segment | Characteristics | Key Needs |
|---------|----------------|-----------|
| **New Members** | Just joined, exploring resources | Onboarding, "what's available", class discovery |
| **Active Students** | Taking weekly classes | Schedule, Zoom links, practice resources, recordings |
| **Experienced Operators** | Advanced members, mentors | Forums, events, community content |
| **Senior Members** | 60-80+ years old | Large text, simple navigation, minimal steps |
| **International Members** | Non-US time zones | Time zone conversion, async content (recordings, newsletters) |

---

## Platform Strategy

### Phase 1: Cross-Platform Mobile (MVP)
- **Framework:** React Native or Flutter
- **Platforms:** iOS 15+ and Android 10+
- **Rationale:** Single codebase, native feel, reaches majority of members

### Phase 2: Web Companion
- Progressive Web App for desktop access
- Shared component library with mobile

### Phase 3: Tablet Optimization
- Enhanced layouts for iPad/Android tablets
- Split-view navigation

---

## Feature Specifications

### 1. Home / Discovery Feed

**Purpose:** Personalized landing page surfacing relevant content

**Content Sources:**
- Upcoming events from calendar (next 7 days)
- New newsletter releases
- Recently added Dropbox content
- Latest podcast episodes
- Pinned announcements

**UI Requirements:**
- Card-based layout with clear hierarchy
- "What's happening now" prominent for live classes
- Pull-to-refresh
- Skeleton loading states (no spinners)

**Personalization (Phase 2):**
- Filter by member's enrolled classes
- Time zone-aware event display
- "Continue where you left off" for videos/podcasts

---

### 2. Calendar / Schedule

**Purpose:** Unified view of all LICW classes, forums, and events

**Data Source:** `cal.longislandcwclub.org` (iCal feed or API)

**Views:**
| View | Description |
|------|-------------|
| **Today** | Default view showing today's schedule with clear time blocks |
| **Week** | 7-day overview with day selection |
| **Month** | Traditional calendar grid with event indicators |
| **List** | Scrollable chronological list (accessibility-friendly) |

**Event Card Information:**
- Event title (e.g., "Beginners 1 - Letters A-F")
- Time with automatic timezone conversion
- Instructor name (if available)
- Event type badge (Class, Forum, Social, Special Event)
- One-tap "Add to Calendar" (native calendar integration)
- One-tap "Join Zoom" (deep link to Zoom app)

**Filtering:**
- By event type (Classes, Forums, Special Events)
- By skill level (Beginner, Intermediate, Advanced)
- By day of week
- Search by event name or instructor

**Smart Features:**
- "Starting Soon" notifications (configurable: 15/30/60 min before)
- Highlight events user has attended before
- Show local time prominently, ET in parentheses

---

### 3. Newsletters Archive

**Purpose:** Browsable, searchable archive of seasonal newsletters

**Data Source:** `longislandcwclub.org/licw-newsletter/` (PDF links)

**Features:**
- Chronological list (newest first)
- Cover image thumbnails
- Season/Year labels (e.g., "Fall 2023")
- In-app PDF viewer
- Download for offline reading
- Share functionality
- Full-text search within newsletters (Phase 2)

**UI:**
- Grid view (2-column) for visual browsing
- List view option for accessibility
- "New" badge for unread newsletters
- Reading progress indicator

---

### 4. Video Library

**Purpose:** Access to class recordings and educational videos

**Data Source:** Dropbox shared folder (`/sh/j63lkeqnuq19wr5/...`)

**Features:**
- Folder hierarchy mirroring Dropbox structure
- Video thumbnails (generated or static)
- Duration and date uploaded
- Search by title/description
- Favorites/bookmarks
- Continue watching (resume playback position)
- Download for offline viewing

**Playback:**
- Native video player integration
- Playback speed controls (0.5x - 2x)
- Skip forward/back (10s/30s configurable)
- Closed captions (if available)
- Picture-in-picture support

**Organization:**
- Categories/playlists (Classes, Forums, Special Events)
- Sort by: Date, Name, Duration, Popularity
- Filter by: Category, Duration, Date Range

---

### 5. Podcast Player

**Purpose:** Listen to "This Week in LICW" podcast

**Data Source:** Buzzsprout RSS feed

**Features:**
- Episode list with descriptions
- Streaming playback
- Download for offline
- Playback speed controls
- Sleep timer
- Background playback
- Lock screen controls
- CarPlay/Android Auto support (Phase 2)

**UI:**
- Mini-player persistent at bottom
- Full-screen player with show notes
- Episode search

---

### 6. Resources Hub

**Purpose:** Quick access to learning tools and reference materials

**Sections:**
| Section | Content |
|---------|---------|
| **Practice Tools** | Link to LICW Morse Practice Page (WebView or external) |
| **Quick References** | Morse code chart, Q-signals, abbreviations |
| **External Links** | AC6V CW Operating Aids, Morse Code Resource Center |
| **Equipment Guides** | What you need for classes, key recommendations |
| **FAQ** | Searchable frequently asked questions |

---

### 7. Search

**Purpose:** Find anything across all content types

**Scope:**
- Calendar events
- Newsletter titles and content (Phase 2)
- Video titles and descriptions
- Podcast episodes
- Resources and FAQ

**Features:**
- Global search bar (accessible from any screen)
- Recent searches
- Search suggestions/autocomplete
- Results grouped by content type
- Filters within results
- Voice search (accessibility)

**Behavior:**
- Fuzzy matching (typo tolerance)
- Instant results as you type
- "No results" state with suggestions

---

### 8. Settings & Preferences

**Options:**
- Time zone selection (auto-detect default)
- Notification preferences (events, new content)
- Display settings (text size, high contrast mode)
- Offline storage management
- Default calendar for event export
- Account linking (Groups.io, future: LICW account)

---

## Navigation Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Tab Bar                          │
├──────────┬──────────┬──────────┬──────────┬────────┤
│   Home   │ Schedule │  Watch   │  Listen  │  More  │
│    🏠    │    📅    │    📺    │    🎧    │   ⋯    │
└──────────┴──────────┴──────────┴──────────┴────────┘

More Menu:
├── Newsletters
├── Resources
├── Search (also in header)
└── Settings
```

**Navigation Principles:**
- Maximum 2 taps to any content
- Persistent tab bar (never hidden)
- Back button always visible
- Clear breadcrumbs in nested views

---

## Data Architecture

### Content Sources & Sync Strategy

| Source | Sync Method | Cache Duration | Offline Support |
|--------|-------------|----------------|-----------------|
| Calendar | iCal subscription + periodic fetch | 1 hour | Yes (7 days) |
| Newsletters | RSS/scrape + PDF cache | 24 hours | Yes (downloaded) |
| Dropbox Videos | Dropbox API | On-demand | Yes (downloaded) |
| Podcast | RSS feed | 1 hour | Yes (downloaded) |
| Resources | Bundled + remote update | Weekly | Yes (bundled) |

### Push Notifications (Phase 2)

| Notification Type | Trigger |
|-------------------|---------|
| Event Reminder | Configurable time before event |
| New Newsletter | On publication |
| New Podcast Episode | On publication |
| Live Event Starting | Class/forum going live |

---

## Accessibility Requirements

### Visual
- [ ] Minimum 16sp/pt base font size
- [ ] Support system font scaling up to 200%
- [ ] 4.5:1 contrast ratio (text), 3:1 (UI elements)
- [ ] No information by color alone
- [ ] Focus indicators visible
- [ ] Reduced motion option

### Motor
- [ ] 44x44pt minimum touch targets
- [ ] No time-limited interactions
- [ ] Single-hand operable
- [ ] No precision gestures required (pinch, etc.)

### Auditory
- [ ] Captions for all video content (where available)
- [ ] Visual indicators for audio content
- [ ] No audio-only alerts

### Cognitive
- [ ] Consistent navigation across screens
- [ ] Clear error messages with recovery actions
- [ ] Progress indicators for multi-step processes
- [ ] Confirmations for destructive actions

---

## Performance Requirements

| Metric | Target |
|--------|--------|
| Cold start | < 2 seconds |
| Screen transitions | < 300ms |
| Search results | < 500ms |
| Calendar load | < 1 second |
| Video start (streaming) | < 3 seconds |

---

## Security & Privacy

- No user accounts required for basic functionality
- Optional account linking for personalization
- No tracking beyond essential analytics
- GDPR/CCPA compliant
- No data sold to third parties
- Local storage encrypted

---

## Success Metrics

### Engagement
- Daily Active Users (DAU)
- Content views per session
- Search success rate (search → content view)
- Feature adoption rates

### Satisfaction
- App Store rating (target: 4.5+)
- User feedback/support tickets
- Task completion rates (e.g., join Zoom from app)

### Discovery
- % of users accessing 3+ content types
- New content discovery rate (views within 48h of publish)
- Search query diversity

---

## Phased Rollout

### MVP (Phase 1) - 12 weeks
- Home feed with basic content aggregation
- Calendar with event details and Zoom links
- Newsletter archive with PDF viewer
- Podcast player (basic)
- Resources hub
- Global search (basic)
- Offline support (calendar, newsletters)

### Phase 2 - 8 weeks post-MVP
- Video library (Dropbox integration)
- Push notifications
- Personalization (followed events, skill level)
- Full-text newsletter search
- Enhanced podcast features

### Phase 3 - 8 weeks post-Phase 2
- Web companion (PWA)
- Tablet-optimized layouts
- CarPlay/Android Auto
- Groups.io integration (announcements)
- Widget support (iOS/Android)

---

## Open Questions

1. **Authentication:** Does LICW have member accounts we can integrate with, or is this purely public content?

2. **Dropbox Access:** What's the best API approach for the shared Dropbox folder? Public links vs. app-level API access?

3. **Calendar Feed:** Is there a machine-readable calendar feed (iCal) available, or do we need to scrape?

4. **Content Moderation:** Who manages what content appears in the app? Is there an admin interface needed?

5. **Notifications:** Does LICW have infrastructure for push notification triggers, or do we poll for changes?

6. **Localization:** Given Spanish classes exist, should the app UI support Spanish (and other languages)?

7. **Analytics:** What analytics platform is acceptable? Any privacy constraints?

---

## Appendix: Content Inventory

### Known LICW Platforms
| Platform | URL | Content Type |
|----------|-----|--------------|
| Main Website | longislandcwclub.org | Info, resources |
| Calendar | cal.longislandcwclub.org | Events, classes |
| Newsletters | longislandcwclub.org/licw-newsletter/ | PDFs |
| Dropbox | dropbox.com/sh/... | Videos |
| Groups.io | groups.io/g/LongIslandCWClub | Discussions |
| Podcast | buzzsprout.com/2178813 | Audio |
| Instagram | @w2lcw | Social |
| Zoom | Various meeting links | Live classes |

---

## References

- [LICW Main Website](https://longislandcwclub.org/)
- [LICW Calendar](https://longislandcwclub.org/events/)
- [LICW Newsletter Archive](https://longislandcwclub.org/licw-newsletter/)
- [LICW Podcast](https://www.buzzsprout.com/2178813)
- [LICW Resources](https://longislandcwclub.org/resources/)
- [CW Class Curriculum](https://longislandcwclub.org/cw-online-classes-forum-curriculum/)
