# Commute section and calendar popup

[`commute.yaml`](commute.yaml) is the complete grid card supplied in `/tmp/dashboard`,
with its three conditional calendar cards wrapped in Button Card. Deploy the Nix
configuration to install Button Card, reload the browser, then paste this file into
the existing grid card's YAML editor. Dashboard layouts remain managed in the UI.
The updated YAML is also saved to `/tmp/dashboard`.

Click anywhere on the visible agenda to open a fullscreen monthly calendar. Click a day
to see that day's events, or an event to see its details. The calendar toolbar
switches between month, day, and agenda views. Clicking the popup title toggles
between wide and fullscreen layouts.

The popup uses a compact month toolbar and event rows, with calendar height based
on the tablet's current viewport, including orientation changes. An explicit
Card Mod wrapper applies styling to the standalone native calendar in Browser Mod.
Its inherited color palette maps Jacob to `#4CAF50`, Sophie to
`#E91E63`, and Bears to `#2196F3` using the same sorted entity list as the calendar.
These colors apply only to the popup; the CalDAV integration remains YAML-managed.
Busy days can still show **+ more** when their events exceed the available space.

Each popup displays all active Home Assistant calendar entities, including all
imported CalDAV calendars. Button Card builds this list from the current entity
states when opening the popup, so newly enabled calendars appear without editing
the dashboard. Disable unwanted calendars in Home Assistant to exclude them.
The compact agendas retain their existing lists and commute visibility rules.

The calendar's **Add event** button opens Home Assistant's built-in event editor.
It supports timed, all-day, multi-day, and recurring events, with calendar selection,
title, description, and location. The picker includes all writable calendars.
Only the browser clicked opens the popup. There is no custom event form or
JavaScript submission handler.

The calendar provider must grant write access. Home Assistant's CalDAV integration
supports creation; editing and deleting existing iCloud events remain in the
calendar provider's app. For all-day events, prefer the UI-configured CalDAV
integration: Home Assistant documents limitations with all-day events in the
default YAML setup. The repository's CalDAV configuration remains unchanged.

The built-in calendar provides the month/day interaction and event editor without
another calendar card.

References: [calendar card](https://www.home-assistant.io/dashboards/calendar/),
[Browser Mod popups](https://github.com/thomasloven/hass-browser_mod/blob/master/documentation/popups.md),
[calendar creation](https://www.home-assistant.io/actions/calendar.create_event/).
