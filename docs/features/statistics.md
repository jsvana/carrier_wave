# Statistics

The dashboard displays QSO statistics with drilldown capability for detailed exploration.

## Dashboard Stats

`QSOStatistics` struct provides grouped statistics:

| Stat Category | Groups by |
|---------------|-----------|
| Bands | Operating frequency band (20m, 40m, etc.) |
| Modes | Transmission mode (SSB, CW, FT8, etc.) |
| DXCC Entities | Country/entity from callsign prefix |
| Parks | POTA park references |

## View Components

### DashboardView

Main entry point showing:
- Activity grid (recent QSO activity)
- Tappable stat cards for each category
- Sync status indicators

### StatDetailView

Drilldown view when tapping a stat card:
- Expandable `StatItemRow` components
- Progressive QSO loading for performance
- Grouped by the selected category

### QSOStatistics

Core struct with `items(for:)` method:
- Takes a `StatCategory` enum
- Returns grouped/counted items
- Used by both dashboard summaries and detail views

## Implementation Notes

- Stats computed on-demand from SwiftData queries
- Large result sets use progressive loading
- `callsignPrefix` extracted for DXCC entity lookup

## Related Plans

- [Statistics Drilldown Design](../plans/2026-01-21-statistics-drilldown-design.md)
- [Statistics Drilldown Implementation](../plans/2026-01-21-statistics-drilldown.md)
