# Zyxel network dashboard

[`zyxel.yaml`](zyxel.yaml) is a complete Home Assistant dashboard using the
`devices_router_zyxel` entities. It uses Mushroom template cards and built-in
cards; Mushroom is already installed by `modules/services/home-assistant.nix`.
The live traffic rates use derivative sensors declared in that module.

## Install

1. Deploy the Nix configuration and restart Home Assistant to load the derivative
   sensors. In **Settings → Dashboards**, create a new empty dashboard and open it.
2. Choose **Edit dashboard → ⋮ → Raw configuration editor**.
3. Paste the entire contents of `zyxel.yaml` and save.

Use a new dashboard so this does not replace an existing layout. To add these
tabs to an existing dashboard, append the three entries under `views:` to its
existing `views:` list instead. This file is a dashboard, not a single card or
`configuration.yaml` snippet. It follows the repository's UI-managed layout
convention and does not register a new dashboard through Nix.

The responsive Sections layout has three tabs:

- **Overview:** WAN status, formatted router uptime, CPU load, memory used,
  firmware, fiber optics, LAN addressing, DHCP client entries, and firewall flags.
- **Traffic:** live receive/send rates automatically formatted as kbit/s, Mbit/s,
  or Gbit/s, five independent received/sent counter totals in decimal GB, and hourly
  transfer charts for the last day. Cyan means received; teal means sent.
  Statistics charts need recorder history and may initially be empty.
- **Diagnostics:** per-interface packet, error, discard, multicast, broadcast,
  and unknown-protocol counters.

## What the source actually provides

Checked the integration's `sensor.py` in the locally packaged revision
`88204c5605abafe246658bf073642afce36ccfbb`, as well as the upstream
[`sensor.py`](https://github.com/zulufoxtrot/ha-zyxel/blob/main/custom_components/ha_zyxel/sensor.py)
and [`api.py`](https://github.com/zulufoxtrot/ha-zyxel/blob/main/custom_components/ha_zyxel/api.py).

The upstream example targets cellular RSSI/SINR entities absent from your list.
Your list exposes GPON optics instead; the overview uses those entities.

`BytesSent` and `BytesReceived` are configured as byte counters with
`state_class: total_increasing`. They are not current bandwidth readings. The
charts use the built-in statistics graph's `change` statistic to show transferred
data per hour, including counter resets handled by Home Assistant. Totals can
reset when the router or interface restarts. Display formatting also handles
Home Assistant's byte-unit overrides.

The ten derivative sensors calculate each counter's rate per second. The cards
convert bytes to bits and select kbit/s below 1,000,000 bit/s, Mbit/s below
1,000,000,000 bit/s, and Gbit/s above that. For example, 80,000 B/s displays as
640 kbit/s, 10,650,000 B/s as 85.2 Mbit/s, and 175,000,000 B/s as 1.4 Gbit/s.
The underlying sensors retain fixed units; only the card display changes units.
This measures traffic in use, averaged between updates, rather than available
internet capacity. Rates need two source readings after startup and may initially
show Unavailable. A one-minute maximum sub-interval recalculates the rate when a
counter stops changing, so idle traffic settles to zero. The
[Derivative integration](https://www.home-assistant.io/integrations/derivative/)
handles resets using the source sensors' `total_increasing` state class. Cards
show Unavailable when the source is unavailable or the rate is invalid.

Configured byte sensors all receive the same friendly name, without the
interface name. Home Assistant resolves collisions with suffixes such as `_2`.
Those suffixes do not guarantee which interface they represent. The dashboard
therefore calls them Counter 1–5 and does not sum them: the same traffic may pass
through multiple interfaces.

To identify each pair, inspect its entity unique ID in Home Assistant's entity
settings or, if that field is not exposed, in a downloaded integration diagnostic
or a read-only copy of the entity registry. The integration constructs the unique
ID as `<entry_id>_<flattened key>`; the key identifies the interface, for example
`traffic.br0.BytesReceived`. The unsuffixed packet entities may correspond to an
empty interface name; do not assume they are WAN. Once verified, rename the
Counter headings in this dashboard to match the actual interfaces.

Other supplied sensors are generic scalar values, without declared units or
measurement classes. Optical readings, link speed, interface uptime, and status
codes are displayed as reported. Confirm units/scaling in the router UI before
interpreting optical readings as dBm or applying thresholds. The router uptime
card follows the upstream example's seconds interpretation. CPU load is shown
without inventing a percentage unit. Memory used is calculated from total and
free memory, so their absolute unit does not matter provided both use the same
unit. DHCP client entries are not necessarily currently online devices. WAN
status is the router's reported state, not an independent internet reachability
test.

Unavailable or nonnumeric values do not become zero in the formatted cards.
Protection flags remain raw values rather than treating arbitrary firmware
strings as enabled. The overview uses one copy of duplicated cardpage/device
data. Provisioning keys, PLOAM passwords, serial numbers, and SIM identifiers are
not included.

## Useful additions

- **Daily and monthly WAN usage:** utility meter helpers on the confirmed WAN
  counters provide calendar-period totals instead of since-reset totals. Do not
  combine the LAN bridge and WAN counters.
- **Internet latency and packet loss:** monitor an external target separately
  from the router. This distinguishes a working LAN from a failing ISP path.
- **DNS response time:** check the resolver you actually use to identify DNS
  failures when the internet path is otherwise working.
- **Optical and system history:** after confirming units, normalized template
  sensors with appropriate units and `state_class: measurement` allow useful
  optical-power, temperature, CPU, and memory graphs. Compare optical thresholds
  against the installed module/ISP specifications.
- **Recent error/discard rates and reboot alerts:** increments per interval
  reveal active faults more clearly than cumulative totals. Uptime drops can
  reveal unexpected restarts. Broadcast/multicast packets per second are more
  informative than their absolute totals.

These additions require helpers or other data sources and are intentionally
not referenced by the ready-to-paste dashboard.
