const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const database = @import("database.zig");

// TODO: don't hardcode paths
const DB_PATH = "/tmp/zkip.db";
const DB_PATH_W = "/tmp/zkip.db.tmp";

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    static.alloc = arena.allocator();

    static.argv = try std.process.argsAlloc(static.alloc);
    defer std.process.argsFree(static.alloc, static.argv);
    defer static.exeFree();

    return if (static.argv.len < 2)
        help()
    else if (std.mem.eql(u8, static.argv[1], "&"))
        if (static.argv.len < 3)
            help()
        else
            forkcmd(static.argv[2..])
    else
        cmd(static.argv[1..]);
}

fn cmd(args: [][:0]u8) !void {
    std.posix.nanosleep(1, 0);
    // zkip init
    if (std.mem.eql(u8, args[0], "init")) {
        _ = try std.io.getStdOut().writer().print(@embedFile("res/init.sh"), .{
            .name = static.name(),
            .exe = try static.exe(),
        });

        // zkip cd <query>
    } else if (std.mem.eql(u8, args[0], "cd")) {
        if (args.len < 2) {
            return;
        }

        if (args.len == 2) {
            const arg = args[1];
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

        const joined = try std.mem.join(static.alloc, " ", args[1..]);
        defer static.alloc.free(joined);

        const rel = std.fs.cwd().realpathAlloc(static.alloc, joined) catch null;
        defer if (rel) |r| static.alloc.free(r);

        const name = rel orelse name: {
            const db = try database.Db.init(static.alloc, DB_PATH);
            defer db.deinit();

            var search: [][]u8 = args[1..];
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

        // zkip query <query>
    } else if (std.mem.eql(u8, args[0], "query")) {
        const db = try database.Db.init(static.alloc, DB_PATH);
        defer db.deinit();
        const entry = db.query(args[1..], static.now());
        if (entry) |e| {
            _ = try std.io.getStdOut().writer().writeAll(e.name);
        } else {
            _ = try std.io.getStdErr().writer().print(
                "{s}: No results.",
                .{static.name()},
            );
        }

        // zkip visit <path>
    } else if (std.mem.eql(u8, args[0], "visit")) {
        // TODO: handle spaces
        // TODO: async
        const name = try std.fs.cwd().realpathAlloc(
            static.alloc,
            if (args.len == 1) "." else args[1],
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

fn forkcmd(args: [][:0]u8) !void {
    // TODO: investigate cross-platform solutions
    if (try std.posix.fork() > 0) {
        std.posix.exit(0);
    } else {
        std.io.getStdOut().close();
        return cmd(args);
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

        return "zskip";
    }

    pub fn cmd() []const u8 {
        if (argv.len == 0) {
            return "zskip";
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
