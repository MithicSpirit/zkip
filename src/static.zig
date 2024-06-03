const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub var alloc: Allocator = undefined;
pub var argv: [][:0]u8 = undefined;
var name_: ?[]const u8 = null;
var exe_: ?[]const u8 = null;
var now_: ?i64 = null;
var here_: ?std.fs.Dir = null;
var dbpath_tmp_: ?[]u8 = undefined;

pub fn name() []const u8 {
    if (name_) |n| {
        return n;
    }

    if (argv.len > 0) blk: {
        const e = exe() catch break :blk;
        const n = std.fs.path.basename(e);
        name_ = n;
        return n;
    }

    return "zkip";
}

pub fn cmd() []const u8 {
    if (argv.len == 0) {
        return "zkip";
    }
    return argv[0];
}

pub fn exe() ![]const u8 {
    if (exe_) |e| {
        return e;
    }

    const e = try std.fs.selfExePathAlloc(alloc);
    exe_ = e;
    return e;
}

pub fn exeFree() void {
    if (exe_) |e| {
        exe_ = null;
        return alloc.free(e);
    }
}

pub fn now() i64 {
    if (now_) |n| {
        return n;
    }

    const n = std.time.milliTimestamp();
    now_ = n;
    return n;
}

pub fn dbpath_tmp() ![]const u8 {
    if (dbpath_tmp_) |path| return path;

    const path = try blk: {
        const entry_type: type = comptime struct { []const u8, []const u8 };
        const entries: [3]entry_type = comptime [_]entry_type{
            .{ "ZKIP_DB", ".tmp" },
            .{ "XDG_CACHE_HOME", "/zkip.db.tmp" },
            .{ "HOME", "/.cache/zkip.db.tmp" },
        };
        inline for (entries) |i| inner: {
            var db = std.process.getEnvVarOwned(alloc, i[0]) catch break :inner;
            const end = db.len;
            const trail: []const u8 = comptime i[1];
            db = alloc.realloc(db, end + trail.len) catch {
                alloc.free(db);
                break :inner;
            };
            @memcpy(db[end..], trail);
            break :blk db;
        }
        break :blk alloc.dupe(u8, "/tmp/zkip.db.tmp");
    };

    dbpath_tmp_ = path;
    return path;
}

pub fn dbpath() ![]const u8 {
    const path = try dbpath_tmp();
    return path[0 .. path.len - 4];
}

pub fn dbpath_free() void {
    if (dbpath_tmp_) |db| {
        dbpath_tmp_ = null;
        return alloc.free(db);
    }
}
