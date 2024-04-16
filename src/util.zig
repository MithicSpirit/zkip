const std = @import("std");

// TODO: add tests for matchAll and matchSingle

pub fn matchAll(haystack: []const u8, needles: []const []const u8) bool {
    if (needles.len == 0) {
        return true;
    }
    if (haystack.len == 0) {
        return false;
    }

    var haystack_ = haystack;
    var needles_ = needles;
    if (std.fs.path.isAbsolute(needles_[0])) {
        const needle = needles_[0];
        if (!std.mem.startsWith(u8, haystack_, needle)) {
            return false;
        }
        needles_ = needles_[1..];
        haystack_ = haystack_[std.mem.indexOfScalarPos(
            u8,
            haystack_,
            needle.len,
            std.fs.path.sep,
        ) orelse needle.len ..];
    }

    var needle: [*]const []const u8 = needles_.ptr + needles_.len - 1;
    while (haystack_.len > 0) {
        if (@intFromPtr(needle) < @intFromPtr(needles_.ptr)) {
            return true;
        }
        if (matchSingle(haystack_, needle[0])) |i| {
            haystack_ = haystack_[0..i];
            needle -= 1;
            continue;
        }
        return false;
    } else {
        return false;
    }
}

fn matchSingle(haystack: []const u8, needle: []const u8) ?usize {
    var i = haystack.len;
    var c: [*]const u8 = needle.ptr + needle.len - 1;
    while (i > 0) {
        if (@intFromPtr(c) < @intFromPtr(needle.ptr)) {
            break;
        }

        i -= 1;
        if (haystack[i] == c[0]) {
            c -= 1;
            continue;
        }
        if (haystack[i] == std.fs.path.sep) {
            return null;
        }
    } else {
        if (@intFromPtr(c) >= @intFromPtr(needle.ptr)) {
            return null;
        }
    }

    if (haystack[i] == std.fs.path.sep) {
        return i;
    }
    if (std.mem.lastIndexOfScalar(u8, haystack[0..i], std.fs.path.sep)) |sepi| {
        return sepi + 1;
    }
    return 0;
}

pub const fakeAlloc: std.mem.Allocator = fakeAlloc: {
    const fakeAllocVtable = struct {
        fn alloc(_: *anyopaque, _: usize, _: u8, _: usize) ?[*]u8 {
            @panic("Attempted to allocate on fake allocator.");
        }
        fn resize(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
            @panic("Attempted to resize on fake allocator.");
        }
        fn free(_: *anyopaque, _: []u8, _: u8, _: usize) void {
            @panic("Attempted to free on fake allocator.");
        }
    };

    break :fakeAlloc .{
        .ptr = undefined,
        .vtable = &.{
            .alloc = fakeAllocVtable.alloc,
            .resize = fakeAllocVtable.resize,
            .free = fakeAllocVtable.free,
        },
    };
};
