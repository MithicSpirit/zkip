const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const static = @import("static.zig");
const database = @import("database.zig");

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
            const dbpath = try static.dbpath();
            defer static.dbpath_free();

            const db = try database.Db.init(static.alloc, dbpath);
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
        const dbpath = try static.dbpath();
        defer static.dbpath_free();

        const db = try database.Db.init(static.alloc, dbpath);
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

        const dbpath_tmp = try static.dbpath_tmp();
        const dbpath = try static.dbpath();
        defer static.dbpath_free();

        var db = try database.DbW.init(static.alloc, dbpath, dbpath_tmp);
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
        std.process.exit(0);
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
