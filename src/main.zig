const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const database = @import("database.zig");

// TODO: don't hardcode paths
const DB_PATH = "/tmp/fascd.db";
const DB_PATH_W = "/tmp/fascd.db.tmp";

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    static.alloc = arena.allocator();

    static.argv = try std.process.argsAlloc(static.alloc);
    defer std.process.argsFree(static.alloc, static.argv);
    defer static.exeFree();

    if (static.argv.len < 2) {
        try help();

        // fascd init
    } else if (std.mem.eql(u8, static.argv[1], "init")) {
        _ = try std.io.getStdOut().writer().print(@embedFile("res/init.sh"), .{
            .name = static.name(),
            .exe = try static.exe(),
        });

        // fascd cd <query>
    } else if (std.mem.eql(u8, static.argv[1], "cd")) {
        if (static.argv.len < 3) {
            return;
        }

        if (static.argv.len == 3) {
            const arg = static.argv[2];
            if (arg.len > 0 and arg[0] == '-') {
                for (arg[1..]) |c| {
                    if (!std.ascii.isDigit(c)) {
                        break;
                    }
                } else {
                    _ = try std.io.getStdOut().writer().writeAll(arg);
                    return;
                }
            }
        }

        const joined = try std.mem.join(static.alloc, " ", static.argv[2..]);
        defer static.alloc.free(joined);

        const rel = std.fs.cwd().realpathAlloc(static.alloc, joined) catch null;
        defer if (rel) |r| static.alloc.free(r);

        const name = rel orelse name: {
            const db = try database.Db.init(static.alloc, DB_PATH);
            defer db.deinit();

            var search: [][]u8 = static.argv[2..];
            const free: ?[]u8 = if (search.len > 0)
                if (std.mem.eql(u8, search[0], "."))
                    std.fs.cwd().realpathAlloc(static.alloc, ".") catch null
                else
                    null
            else
                null;
            defer if (free) |f| static.alloc.free(f);
            if (free) |f| search[0] = f;

            const entry = db.query(search, static.now());
            break :name if (entry) |e| e.name else joined;
        };
        _ = try std.io.getStdOut().writer().writeAll(name);

        // fascd query <query>
    } else if (std.mem.eql(u8, static.argv[1], "query")) {
        const db = try database.Db.init(static.alloc, DB_PATH);
        defer db.deinit();
        const entry = db.query(static.argv[2..], static.now());
        if (entry) |e| {
            _ = try std.io.getStdOut().writer().writeAll(e.name);
        } else {
            _ = try std.io.getStdErr().writer().print(
                "{s}: No results.",
                .{static.name()},
            );
        }

        // fascd visit <path>
    } else if (std.mem.eql(u8, static.argv[1], "visit")) {
        // TODO: handle spaces
        // TODO: async
        const name = try std.fs.cwd().realpathAlloc(
            static.alloc,
            if (static.argv.len == 2) "." else static.argv[2],
        );
        defer static.alloc.free(name);

        var db = try database.DbW.init(static.alloc, DB_PATH, DB_PATH_W);
        defer db.deinit();
        try db.visit(name, static.now());
        try db.write();

        // fallback
    } else {
        try help();
    }
}

fn help() !void {
    _ = try std.io.getStdErr().writer().print(
        @embedFile("res/help.txt"),
        .{ .cmd = static.cmd() },
    );
}

const static = struct {
    pub var alloc: Allocator = undefined;
    pub var argv: [][:0]u8 = undefined;
    var name_: ?[]const u8 = null;
    var exe_: ?[]const u8 = null;
    var now_: ?i64 = null;
    var here_: ?std.fs.Dir = null;

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

        return "fasdc";
    }

    pub fn cmd() []const u8 {
        if (argv.len == 0) {
            return "fasdc";
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
};
