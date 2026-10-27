# ⚡ ProcPilot — Lightweight Linux System Monitor

> A terminal monitor that reads Linux `/proc` directly, written in Zig.

**Repository:** `procpilot-zig`  
**GitHub description:** Lightweight Linux system monitor built with Zig, featuring CPU usage, RAM, uptime, load averages and top processes.

## Features included

- Overall CPU usage sampled across two `/proc/stat` snapshots
- Used vs total RAM from `/proc/meminfo` (uses `MemAvailable`)
- System uptime, 1/5/15-minute load averages
- Process table sorted by resident memory use
- Single-shot terminal output or refreshing watch mode
- Parser unit tests, no runtime packages or privileged access required

## Requirements

- **Zig 0.13.0** (source and `build.zig` target this version)
- Linux (or WSL2 with `/proc` mounted). **Not natively supported on Windows/macOS**

Note: Zig introduces breaking standard-library changes between some versions. Use the pinned Zig version above rather than assuming the latest 0.17 release is compatible.

## Build & run

```bash
cd ProcPilot-Zig
zig build
./zig-out/bin/procpilot

# Interactive watch mode:
./zig-out/bin/procpilot --watch 2

# Run unit tests:
zig build test
```

Or:

```bash
zig build run -- --once
zig build run -- --watch 3
```

## Data sources

| Metric | Kernel interface |
|---|---|
| CPU | `/proc/stat` |
| Memory | `/proc/meminfo` |
| Uptime | `/proc/uptime` |
| Load | `/proc/loadavg` |
| Process names & states | `/proc/PID/comm`, `/proc/PID/status` |

## Project structure

```text
ProcPilot-Zig/
  build.zig
  src/main.zig
  README.md
```

## Limitations

- Shows total host CPU percentage, not per-core or per-process CPU usage.
- Some process details may be unavailable due to kernel permissions or process exit races; such entries are skipped.
- Watch mode clears an ANSI-compatible terminal; use Ctrl+C to exit.
- As in many system monitors, rapidly changing values are approximate samples.
- No network services or root permissions are needed.

## Suggested GitHub topics

`zig` `linux` `system-monitor` `cli` `procfs` `systems-programming`

## License

MIT — see [LICENSE](LICENSE) in this folder.
