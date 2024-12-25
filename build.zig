const std = @import("std");

var gpaimpl = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpaimpl.allocator();

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dnum = try find_target_day(b);
    try create_day_sources(b, dnum);

    const day_src_path = try std.fmt.allocPrint(gpa, "src/day{}.zig", .{ dnum });

    const dmod = b.addModule("aoc-day", .{
        .root_source_file = b.path(day_src_path),
    });
    // std.log.info("Adding day module. Name: aoc-day, Source file: {s}", .{ day_src_path });

    const exe = b.addExecutable(.{
        .name = "aoc-zig",
        .root_source_file = b.path("templates/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("aoc-day", dmod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

const day_cache_fname = "daycache.txt";

fn find_target_day(b: *std.Build) !u32 {
    // First check if there is a specified day as an option
    var dopt = b.option(u32, "day", "Advent of code target day");

    const should_read_cache = dopt == null;

    // See if there is a cached file with the last day
    const day_cache_file = try b.cache_root.handle.createFile(day_cache_fname, .{
        .read = should_read_cache,
        .truncate = !should_read_cache
    });
    defer day_cache_file.close();

    if (dopt == null) {
        const content = try day_cache_file.readToEndAlloc(gpa, 10 * 1024 * 1024);
        defer gpa.free(content);

        dopt = std.fmt.parseUnsigned(u32, content, 10) catch null;

        // Make sure we override the file
        try day_cache_file.seekTo(0);
        try day_cache_file.setEndPos(0);
    }

    if (dopt == null) {
        // If all else failed, find the latest day in the src directory
        var i: u32 = 25;
        dopt = blk: while (i > 0) : (i -= 1) {
            var daybuff: ["src/dayXX.zig".len]u8 = undefined;
            const daystr = try std.fmt.bufPrint(daybuff[0..], "src/day{}.zig", .{ i });
            b.build_root.handle.access(daystr, .{}) catch continue;
            break :blk i;
        } else null;
    }

    const dnum = dopt orelse 1;
    var dbuf: [2]u8 = undefined;
    const dstr = try std.fmt.bufPrint(dbuf[0..], "{}", .{ dnum });
    try day_cache_file.writeAll(dstr);

    return dnum;
}

fn create_day_sources(b: *std.Build, dnum: u32) !void {
    const root = b.build_root.handle;

    // Ensure we have both a src and a src/data directories
    try root.makePath("src/data");

    var srcbuf: ["src/dayXX.zig".len]u8 = undefined;
    var inpbuf: ["src/data/inputXX.txt".len]u8 = undefined;
    const srcpath = try std.fmt.bufPrint(srcbuf[0..], "src/day{}.zig", .{ dnum });
    const inppath = try std.fmt.bufPrint(inpbuf[0..], "src/data/input{}.txt", .{ dnum });

    // std.log.info("Searching or creating day files. Src: {s}, Input: {s}", .{ srcpath, inppath });

    root.access(srcpath, .{}) catch {
        const daycode = try create_day_source_from_code(gpa, @embedFile("templates/day.zig"), dnum);
        defer gpa.free(daycode);

        // std.log.info("Day code:\n{s}", .{ daycode });

        const srcfile = try root.createFile(srcpath, .{});
        defer srcfile.close();

        try srcfile.writeAll(daycode);
    };

    root.access(inppath, .{}) catch {
        const inpfile = try root.createFile(inppath, .{});
        inpfile.close();
    };
}

const SourceGenError = error {
    UnexpectedVariableStart,
    MissingVariableEnd,
    UnknownVariable,
};

fn create_day_source_from_code(alloc: std.mem.Allocator, template: []const u8, daynum: u32) ![]const u8 {
    var text = std.ArrayList([]const u8).init(alloc);
    defer text.deinit();

    var daybuf: [2]u8 = undefined;
    const daystr = try std.fmt.bufPrint(daybuf[0..], "{}", .{ daynum });

    var current = template;
    while (std.mem.indexOfScalar(u8, current, '$')) |index| {
        try text.append(current[0..index]);
        current = current[index + 1..];

        if (current.len < 3 or current[0] != '{') {
            std.log.err("Unexpected variable start at: {s}", .{ current });
            return SourceGenError.UnexpectedVariableStart;
        }

        const var_end = std.mem.indexOfScalar(u8, current, '}') orelse return SourceGenError.MissingVariableEnd;

        const variable = current[1..var_end];
        current = current[var_end + 1..];

        if (std.mem.eql(u8, variable, "day")) {
            try text.append(daystr);
        } else {
            return SourceGenError.UnknownVariable;
        }
    }

    if (current.len > 0)
        try text.append(current);

    return try std.mem.concat(alloc, u8, text.items);
}
