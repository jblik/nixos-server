# Commute section and calendar popup

[`commute.yaml`](commute.yaml) is the complete grid card supplied in `/tmp/dashboard`,
with its three conditional calendar cards wrapped in Button Card. Deploy the Nix
configuration to install Button Card, reload the browser, then paste this file into
the existing grid card's YAML editor. Dashboard layouts remain managed in the UI.
The updated YAML is also saved to `/tmp/dashboard`.

Click anywhere on the visible agenda to open a wide monthly calendar. Click a day
to see that day's events, or an event to see its details. The calendar toolbar
switches between month, day, and agenda views. Clicking the popup title toggles
between wide and fullscreen layouts.

Each popup displays exactly its agenda's entities. The seven-row variant includes
Jacob, Sophie, Bears, and Sophie Uni; the four-row and one-row variants include
Jacob, Sophie, and Bears. Existing commute visibility rules are preserved.

**New event** opens a form with a calendar picker restricted to those same entities,
title, start and end date/time, description, and location. It creates a timed event
using `calendar.create_event`. Dates without an explicit offset use Home Assistant's
configured time zone. A failed save keeps the form open and displays the error;
a successful save closes it and shows a confirmation. Use Cancel to return to the
month without saving. Only the browser clicked opens the popup.

The form uses Browser Mod's JavaScript action, which must be permitted for the
browser. No credentials or additional calendar integration are needed. The
calendar provider must grant write access. Home Assistant's CalDAV integration
supports creation; editing and deleting existing iCloud events remain in the
calendar provider's app. This form does not create all-day or recurring events.

The built-in calendar is used for the popup because it provides the month/day
interaction without another calendar card. Its native Add event dialog searches
all writable calendars, so this section uses its own restricted creation form.

References: [calendar card](https://www.home-assistant.io/dashboards/calendar/),
[Browser Mod popups](https://github.com/thomasloven/hass-browser_mod/blob/master/documentation/popups.md),
[calendar creation](https://www.home-assistant.io/actions/calendar.create_event/).
