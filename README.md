🖥️ ProcPilot
A lightweight Linux system monitor written in Zig.

ProcPilot is a command-line project concept for viewing essential Linux system information without a heavyweight monitoring stack. It focuses on efficient system programming, direct interaction with Linux's virtual filesystems, and clear terminal output.
Status: Planned project — commands and features are targets for the implementation.

✨ Planned Features
- [ ] Display CPU utilization and memory usage
- [ ] Read system uptime and load averages
- [ ] List the busiest processes by CPU or memory
- [ ] Refresh terminal metrics at a configurable interval
- [ ] Export a system snapshot as JSON
- [ ] Handle missing files and permission errors cleanly
🛠️ Tech Stack
Area	Technology
Language	Zig
Platform	Linux
Data sources	/proc and /sys
Interface	Terminal / CLI
Dependencies	Zig standard library where practical


⚙️ Design
ProcPilot will read Linux-provided metrics, parse the values in Zig, calculate usage between samples when necessary, and render a compact terminal dashboard.
Linux /proc + /sys
        |
        v
  Zig metric parsers
        |
        v
  Terminal dashboard
        |
        +--> Optional JSON snapshot
🚀 Getting Started (After Implementation)
Prerequisites: Linux and a compatible Zig compiler. The final code will document the supported Zig version.
git clone https://github.com/dinusha/procpilot-zig.git
cd procpilot-zig
zig build
zig build run
🗺️ Development Roadmap
Phase 1: CPU, RAM, uptime, and load-average readers.
Phase 2: Process listing and refreshable terminal view.
Phase 3: Filtering, CLI flags, JSON export, and tests.
🎯 Learning Goals
Memory management, file I/O, Linux process information, efficient parsing, command-line design, and defensive error handling in Zig.
Built as a software engineering portfolio project.
