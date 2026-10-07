# sysmon — system pressure monitor

Early warning for "the machine technically works but is unusable" situations
(memory thrashing, swap exhaustion, I/O stalls, CPU saturation), plus a 7-day
history for post-mortem analysis.

**sysmon only observes, logs and notifies.** It never kills processes, restarts
services, drops caches or changes system settings.

## Components

| Part | Runs as | Purpose |
|---|---|---|
| `sysmon.service` | root, system service, starts at boot | samples every 5 s from `/proc` + `/sys`, evaluates rules, writes history/snapshots/events |
| `sysmon-notify.service` | your user, user service | turns events into desktop notifications (`notify-send`) |
| `sysmon status / history / events / snapshots` | anyone | CLI viewers (work from a TTY) |

The daemon does not depend on the GUI. During a stall it keeps running because:
- its memory is locked in RAM (`mlockall`), so it can't be thrashed out
- it is protected from the OOM killer (`OOMScoreAdjust=-900`, only this process) and runs at `Nice=-10`
- it never forks or calls D-Bus while sampling
- history writes happen in a separate thread with `fdatasync`, so data survives a hard reset

## Files

- `/etc/sysmon.conf`: all thresholds (`sudo systemctl restart sysmon` after editing; `sysmon config` validates)
- `/var/log/sysmon/history-YYYYMMDD-HH.csv`: one row per 5 s. Kept for 7 days, capped at 100 MB.
- `/var/log/sysmon/events.log`: state changes (JSON lines)
- `/var/log/sysmon/snapshots/*.txt`: detailed diagnostics. Up to 300 files / 150 MB.
- `/run/sysmon/state.json`, `/run/sysmon/events.jsonl`: live state (RAM only)
- journald: `journalctl -u sysmon` (state changes only)

History and snapshot writing pauses automatically if the filesystem has less
than 2 GB free. Old files are removed by age and total size. Nothing outside
`/var/log/sysmon` is ever deleted.

## After a freeze

```
sysmon events -v                            # what alerts fired, with details
sysmon history --since "10:25" --until "10:55"
sysmon history --since 2h --every 6         # every 30 s
sysmon history --since 1d --csv > h.csv     # all columns for a spreadsheet
sysmon snapshots                            # then: less /var/log/sysmon/snapshots/<file>
journalctl -b -1 -u sysmon                  # previous boot's monitor log
journalctl -b -1 -k | grep -i -e oom -e blocked   # kernel side
```

A `dt` column (sample interval) much larger than 5 means the monitor itself
was starved. That alone is a strong stall indicator.

## Signals

States: NORMAL → WARNING → CRITICAL → RECOVERY. Two independent channels:
**pressure** (memory / I/O / CPU) and **disk space**.

- **RAM trend:** headroom = MemAvailable + SwapFree − 3% floor. The slope is a Theil–Sen
  (median of pairwise slopes) estimate over 90 s, so short spikes are ignored.
  Predicted exhaustion < 5 min → WARNING; < 90 s → CRITICAL. The prediction is
  armed only once available RAM is below 30%.
- **PSI** (`/proc/pressure`): the share of time tasks were stalled on memory, I/O or CPU. "full" means
  all non-idle tasks were stalled at once, i.e. the desktop is frozen.
- **Swap usage and activity**, **thrashing** (workingset refaults), **direct reclaim**,
  **major faults**, **OOM kills**.
- **Blocked tasks** (`procs_blocked`, D-state), **disk util + iowait**, **load / cores**.
- **Combination:** WARNING in two or more of memory / I/O / CPU escalates to CRITICAL
  (for example "memory + I/O").

Notification rules:
- notified on entering WARNING, entering CRITICAL, and on RECOVERY (60 s clear)
- no repeats while the state is unchanged
- one "update" if a new signal (such as the RAM-exhaustion prediction) appears during WARNING
- a WARNING within 5 min of a recovery is logged but not notified

Optional TTY broadcast of CRITICAL alerts: `wall_on_critical = yes` in `/etc/sysmon.conf`.

## Testing

```
sysmon selftest -v        # simulated scenarios through the real alert logic (no load)
sysmon notify --test      # one test desktop notification
sudo sysmon snapshot      # force a diagnostic snapshot now
```

## Remove

`sudo ./uninstall.sh` (keeps history), or `sudo ./uninstall.sh --purge`.
