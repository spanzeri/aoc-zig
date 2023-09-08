const std = @import("std");

var gpaimpl = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpaimpl.allocator();

const data = @embedFile("data/input${day}.txt");

pub fn solution1() !void {
    std.debug.print("Solution 1: \n", .{});
}

pub fn solution2() !void {
    std.debug.print("Solution 2: \n", .{});
}
