// TODO: rewrite database system (read-only v. read-write)
const std = @import("std");
const Allocator = std.mem.Allocator;

const util = @import("util.zig");

const Entry = struct {
    time: i64,
    count: i64,
    name: []const u8,

    const BufLE = packed struct {
        time: i64,
        count: i64,
        len: usize,
    };
    const bufSize: usize = @sizeOf(BufLE) / @sizeOf(u8);

    pub fn readFrom(heap: []const u8) ?struct { Entry, usize } {
        if (bufSize > heap.len) {
            @panic("");
        }

        const buf = std.mem.bytesAsValue(BufLE, heap[0..bufSize]);
        const len = std.mem.littleToNative(usize, buf.len);
        const total = bufSize + len;
        if (total > heap.len) {
            @panic("");
        }

        return .{ .{
            .time = std.mem.littleToNative(i64, buf.time),
            .count = std.mem.littleToNative(i64, buf.count),
            .name = heap[bufSize .. bufSize + len],
        }, total };
    }

    pub fn writeTo(self: *const @This(), writer: *std.fs.File.Writer) !usize {
        const buf_: BufLE = .{
            .time = std.mem.nativeToLittle(i64, self.time),
            .count = std.mem.nativeToLittle(i64, self.count),
            .len = std.mem.nativeToLittle(usize, self.name.len),
        };
        const buf = std.mem.asBytes(&buf_);

        try writer.writeAll(buf);
        try writer.writeAll(self.name);
        return bufSize + self.name.len;
    }

    pub fn value(self: *const @This(), now: i64) i64 {
        const delta = now - self.time;
        if (delta < std.time.ms_per_hour) {
            return self.count <<| 3;
        }
        if (delta < std.time.ms_per_day) {
            return self.count <<| 2;
        }
        if (delta < std.time.ms_per_week) {
            return self.count <<| 1;
        }
        return self.count;
    }

    pub fn visit(self: *@This(), now: i64) void {
        self.time = now;
        self.add(1);
    }

    pub fn add(self: *@This(), count: i64) void {
        self.count +|= count;
    }
};

pub const Db = struct {
    alloc: Allocator,
    heap: []const u8,
    entries: []const Entry,

    pub fn init(alloc: Allocator, path: []const u8) !@This() {
        const file = try std.fs.createFileAbsolute(path, .{
            .read = true,
            .truncate = false,
        });
        defer file.close();
        // TODO: do something about maxsize?
        const heap = try file.readToEndAlloc(alloc, 1 << 21);
        return .{
            .alloc = alloc,
            .heap = heap,
            .entries = try getEntries(alloc, heap),
        };
    }

    pub fn deinit(self: *const @This()) void {
        defer self.alloc.free(self.heap);
        defer self.alloc.free(self.entries);
    }

    pub fn find(self: *const @This(), name: []const u8) ?*const Entry {
        for (self.entries) |*e| {
            if (std.mem.eql(u8, e.name, name)) {
                return e;
            }
        }
        return null;
    }

    pub fn query(
        self: *const @This(),
        search: []const []const u8,
        now: i64,
    ) ?*const Entry {
        var maxEntry: ?*const Entry = null;
        var maxVal: i64 = std.math.minInt(i64);
        var maxDate: i64 = std.math.minInt(i64);
        for (self.entries) |*e| {
            const v = e.value(now);
            if (maxVal > v) {
                continue;
            }
            if (maxVal == v and maxDate > e.time) {
                continue;
            }

            if (util.matchAll(e.name, search)) {
                maxEntry = e;
                maxVal = v;
                maxDate = e.time;
            }
        }
        return maxEntry;
    }

    fn getEntries(alloc: Allocator, heap: []const u8) ![]Entry {
        var i: usize = 0;
        var entries = try std.ArrayList(Entry)
            .initCapacity(alloc, heap.len / 32);
        errdefer entries.deinit();

        while (i < heap.len) {
            if (Entry.readFrom(heap[i..])) |res| {
                try entries.append(res[0]);
                i += res[1];
                continue;
            }
            break;
        }
        return try entries.toOwnedSlice();
    }
};

pub const DbW = struct {
    alloc: Allocator,
    heap: []const u8,
    entries: std.ArrayList(Entry),
    pathR: []const u8,
    pathW: []const u8,
    fileW: std.fs.File,

    pub fn init(alloc: Allocator, pathR: []const u8, pathW: []const u8) !@This() {
        const fileW = try std.fs.createFileAbsolute(pathW, .{
            .read = false,
            .truncate = false,
            .exclusive = true,
            .lock = .exclusive,
            .lock_nonblocking = false,
        });
        errdefer std.fs.deleteFileAbsolute(pathW) catch {};
        errdefer fileW.close();

        var db = try Db.init(alloc, pathR);
        return .{
            .alloc = db.alloc,
            .heap = db.heap,
            .entries = std.ArrayList(Entry).fromOwnedSlice(
                alloc,
                @constCast(db.entries),
            ),
            .pathR = pathR,
            .pathW = pathW,
            .fileW = fileW,
        };
    }

    fn intoDb(self: *const @This()) Db {
        return .{
            .alloc = util.fakeAlloc,
            .heap = self.heap,
            .entries = self.entries.items,
        };
    }

    pub fn write(self: *@This()) !void {
        try self.fileW.seekTo(0);
        try self.fileW.setEndPos(0);

        var writer = self.fileW.writer();
        for (self.entries.items) |entry| {
            // TODO: implement pruning
            // TODO: implement maxsize
            _ = try entry.writeTo(&writer);
        }

        try self.fileW.sync();
        try std.fs.copyFileAbsolute(self.pathW, self.pathR, .{});
    }

    pub fn deinit(self: @This()) void {
        defer self.alloc.free(self.heap);
        defer self.entries.deinit();
        defer self.fileW.close();
        defer std.fs.deleteFileAbsolute(self.pathW) catch {};
    }

    pub fn find(self: *const @This(), name: []const u8) ?*Entry {
        return @constCast(self.intoDb().find(name));
    }

    pub fn visit(self: *@This(), name: []const u8, now: i64) !void {
        if (self.find(name)) |entry| {
            entry.visit(now);
            return;
        }
        try self.entries.append(.{
            .time = now,
            .count = 1,
            .name = name,
        });
    }
};
