const std = @import("std");
const builtin = @import("builtin");

const CpuSample = struct {
    total: u64,
    idle: u64,
};

const MemSample = struct {
    total_kb: u64 = 0,
    available_kb: u64 = 0,
};

const Process = struct {
    pid: u32,
    name: []const u8,
    state: []const u8,
    rss_kb: u64,
};

const max_file_bytes = 64 * 1024;

fn readText(allocator: std.mem.Allocator, absolute_path: []const u8) ![]u8 {
    var file = try std.fs.openFileAbsolute(absolute_path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_file_bytes);
}

fn parseCpu(text: []const u8) !CpuSample {
    var lines = std.mem.splitScalar(u8, text, '\n');
    const first = lines.next() orelse return error.InvalidCpuData;
    var parts = std.mem.tokenizeAny(u8, first, " \t");
    if (!std.mem.eql(u8, parts.next() orelse "", "cpu")) return error.InvalidCpuData;
    var total: u64 = 0;
    var idle: u64 = 0;
    var i: usize = 0;
    while (parts.next()) |part| : (i += 1) {
        const value = try std.fmt.parseInt(u64, part, 10);
        total += value;
        if (i == 3 or i == 4) idle += value;
    }
    if (i < 4 or total == 0) return error.InvalidCpuData;
    return .{ .total = total, .idle = idle };
}

fn readCpu(allocator: std.mem.Allocator) !CpuSample {
    const text = try readText(allocator, "/proc/stat");
    defer allocator.free(text);
    return parseCpu(text);
}

fn cpuPercentage(before: CpuSample, after: CpuSample) f64 {
    if (after.total <= before.total) return 0;
    const total_delta = after.total - before.total;
    const idle_delta = if (after.idle > before.idle) after.idle - before.idle else 0;
    const busy = total_delta - @min(total_delta, idle_delta);
    return (@as(f64, @floatFromInt(busy)) * 100.0) / @as(f64, @floatFromInt(total_delta));
}

fn firstNumber(text: []const u8) ?u64 {
    var parts = std.mem.tokenizeAny(u8, text, " \t:\r\n");
    while (parts.next()) |part| {
        if (std.fmt.parseInt(u64, part, 10)) |n| return n else |_| {}
    }
    return null;
}

fn parseMem(text: []const u8) MemSample {
    var result = MemSample{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            result.total_kb = firstNumber(line) orelse 0;
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            result.available_kb = firstNumber(line) orelse 0;
        }
    }
    return result;
}

fn readMem(allocator: std.mem.Allocator) !MemSample {
    const text = try readText(allocator, "/proc/meminfo");
    defer allocator.free(text);
    const sample = parseMem(text);
    if (sample.total_kb == 0) return error.InvalidMemoryData;
    return sample;
}

fn readUptimeSeconds(allocator: std.mem.Allocator) !u64 {
    const text = try readText(allocator, "/proc/uptime");
    defer allocator.free(text);
    var parts = std.mem.tokenizeAny(u8, text, " \t\n");
    const value = try std.fmt.parseFloat(f64, parts.next() orelse return error.InvalidUptime);
    return @intFromFloat(value);
}

fn readLoad(allocator: std.mem.Allocator) ![3]f64 {
    const text = try readText(allocator, "/proc/loadavg");
    defer allocator.free(text);
    var parts = std.mem.tokenizeAny(u8, text, " \t\n");
    var values: [3]f64 = undefined;
    for (&values) |*value| {
        value.* = try std.fmt.parseFloat(f64, parts.next() orelse return error.InvalidLoadData);
    }
    return values;
}

fn readProcess(allocator: std.mem.Allocator, pid: u32) ?Process {
    const comm_path = std.fmt.allocPrint(allocator, "/proc/{d}/comm", .{pid}) catch return null;
    const status_path = std.fmt.allocPrint(allocator, "/proc/{d}/status", .{pid}) catch return null;
    const raw_name = readText(allocator, comm_path) catch return null;
    const status = readText(allocator, status_path) catch return null;
    const name = std.mem.trim(u8, raw_name, " \r\n");
    var rss: u64 = 0;
    var state: []const u8 = "?";
    var lines = std.mem.splitScalar(u8, status, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "VmRSS:")) {
            rss = firstNumber(line) orelse 0;
        } else if (std.mem.startsWith(u8, line, "State:")) {
            var parts = std.mem.tokenizeAny(u8, line, " \t");
            _ = parts.next();
            state = parts.next() orelse "?";
        }
    }
    return .{ .pid = pid, .name = name, .state = state, .rss_kb = rss };
}

fn byMemory(_: void, lhs: Process, rhs: Process) bool {
    return lhs.rss_kb > rhs.rss_kb;
}

fn listProcesses(allocator: std.mem.Allocator) ![]Process {
    var proc_dir = try std.fs.openDirAbsolute("/proc", .{ .iterate = true });
    defer proc_dir.close();
    var iterator = proc_dir.iterate();
    var list = std.ArrayList(Process).init(allocator);
    while (try iterator.next()) |entry| {
        if (entry.kind != .directory) continue;
        const pid = std.fmt.parseInt(u32, entry.name, 10) catch continue;
        if (readProcess(allocator, pid)) |process| try list.append(process);
    }
    std.sort.pdq(Process, list.items, {}, byMemory);
    return list.toOwnedSlice();
}

fn renderSnapshot(clear: bool) !void {
    // Each snapshot uses an arena, so all /proc buffers are reclaimed at once.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const before = try readCpu(allocator);
    std.time.sleep(300 * std.time.ns_per_ms);
    const after = try readCpu(allocator);
    const mem = try readMem(allocator);
    const uptime = try readUptimeSeconds(allocator);
    const load = try readLoad(allocator);
    const processes = try listProcesses(allocator);

    if (clear) std.debug.print("\x1b[2J\x1b[H", .{});
    std.debug.print("\n ╭─────────────────────────────────────────────────────╮\n", .{});
    std.debug.print(" │  PROC PILOT     Linux System Monitor  •  Zig 0.13   │\n", .{});
    std.debug.print(" ╰─────────────────────────────────────────────────────╯\n\n", .{});
    const used_kb = mem.total_kb - @min(mem.total_kb, mem.available_kb);
    const percentage = (@as(f64, @floatFromInt(used_kb)) * 100.0) / @as(f64, @floatFromInt(mem.total_kb));
    std.debug.print(" CPU usage       : {d:.1}%\n", .{cpuPercentage(before, after)});
    std.debug.print(" Memory used     : {d:.1}%  ({d} / {d} MiB)\n", .{
        percentage, used_kb / 1024, mem.total_kb / 1024,
    });
    std.debug.print(" Load (1/5/15m) : {d:.2}  {d:.2}  {d:.2}\n", .{ load[0], load[1], load[2] });
    std.debug.print(" Uptime          : {d}d {d}h {d}m\n", .{ uptime / 86400, (uptime % 86400) / 3600, (uptime % 3600) / 60 });
    std.debug.print(" Processes       : {d} visible\n\n", .{processes.len});
    std.debug.print(" TOP PROCESSES BY RESIDENT MEMORY\n", .{});
    std.debug.print(" PID\t  RSS(MiB)\tSTATE\tNAME\n", .{});
    std.debug.print(" ────────────────────────────────────────────────\n", .{});
    for (processes[0..@min(processes.len, 10)]) |process| {
        const truncated = if (process.name.len > 29) process.name[0..29] else process.name;
        std.debug.print(" {d}\t  {d}\t\t{s}\t{s}\n", .{ process.pid, process.rss_kb / 1024, process.state, truncated });
    }
    std.debug.print("\n Tip: procpilot --watch 2   |   Ctrl+C to exit\n\n", .{});
}

fn usage() void {
    std.debug.print(
        "ProcPilot — Linux terminal system monitor\n" ++
        "Usage:\n" ++
        "  procpilot               One snapshot\n" ++
        "  procpilot --once        One snapshot\n" ++
        "  procpilot --watch 2     Refresh every 2 seconds (1–60)\n" ++
        "  procpilot --help        Show this help\n" ++
        "Requires Linux /proc. Compiles with Zig 0.13.0.\n",
        .{},
    );
}

pub fn main() !void {
    if (builtin.os.tag != .linux) {
        std.debug.print("ProcPilot requires Linux with mounted /proc.\n", .{});
        return error.UnsupportedPlatform;
    }
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1 or (args.len == 2 and std.mem.eql(u8, args[1], "--once"))) {
        try renderSnapshot(false);
        return;
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        usage();
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "--watch")) {
        const seconds = std.fmt.parseInt(u64, args[2], 10) catch {
            usage();
            return error.InvalidInterval;
        };
        if (seconds < 1 or seconds > 60) return error.InvalidInterval;
        while (true) {
            try renderSnapshot(true);
            std.time.sleep(seconds * std.time.ns_per_s);
        }
    }
    usage();
    return error.InvalidArguments;
}

test "parse proc stat and compute busy percentage" {
    const start = try parseCpu("cpu 10 0 20 70 0 0 0 0 0 0\n");
    const finish = try parseCpu("cpu 20 0 40 140 0 0 0 0 0 0\n");
    try std.testing.expectApproxEqAbs(@as(f64, 30.0), cpuPercentage(start, finish), 0.0001);
}

test "parse memory info" {
    const mem = parseMem("MemTotal: 4096000 kB\nMemAvailable: 1024000 kB\n") ;
    try std.testing.expectEqual(@as(u64, 4096000), mem.total_kb);
    try std.testing.expectEqual(@as(u64, 1024000), mem.available_kb);
}

test "parse first numeric field" {
    try std.testing.expectEqual(@as(?u64, 12345), firstNumber("VmRSS: 12345 kB"));
    try std.testing.expectEqual(@as(?u64, null), firstNumber("no numeric data"));
}
