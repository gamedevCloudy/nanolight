//! File lookups run off the main thread; answers move their icons to the view.
const std = @import("std");
const nanoui = @import("nanoui");
const files = @import("files.zig");
const suggest = @import("suggest.zig");
const Live = @import("main.zig").Live;
const mac = @import("builtin").os.tag == .macos;

/// File lookups share the suggestions' pause and keep at most one worker.
pub fn askFiles(ctx: *anyopaque, q: []const u8) void {
    if (!mac or q.len >= files.max_path) return;
    const l: *Live = @ptrCast(@alignCast(ctx));
    @memcpy(l.files.query[0..q.len], q);
    l.files.len = q.len;
    l.files.epoch +%= 1;
    l.files.waiting += 1;
    nanoui.App.after(suggest.pause_ms, l, struct {
        fn f(c: ?*anyopaque) callconv(.c) void {
            const live: *Live = @ptrCast(@alignCast(c.?));
            live.files.waiting -= 1;
            if (live.files.waiting == 0) sendFiles(live);
        }
    }.f);
}

fn sendFiles(l: *Live) void {
    if (!mac or l.files.busy or l.files.waiting > 0 or l.files.sent == l.files.epoch or !l.s.files_on) return;
    const q = l.files.query[0..l.files.len];
    if (!std.mem.eql(u8, q, std.mem.trim(u8, l.s.query.text(), " \t\r\n"))) return;
    const a = l.app.gpa.create(FileAsk) catch return;
    a.* = .{ .live = l, .len = q.len, .epoch = l.files.epoch, .found = .{ .allocator = l.app.gpa } };
    @memcpy(a.text[0..q.len], q);
    a.locations = l.kv.get(l.app.gpa, files.locations_key) catch null;
    a.exclusions = l.kv.get(l.app.gpa, files.exclusions_key) catch null;
    l.files.busy = true;
    l.files.sent = l.files.epoch;
    const thread = std.Thread.spawn(.{}, FileAsk.run, .{a}) catch {
        l.files.busy = false;
        a.destroy();
        return;
    };
    thread.detach();
}

/// One file query, with all filesystem, process and icon work off the UI thread.
const FileAsk = struct {
    live: *Live,
    text: [files.max_path]u8 = undefined,
    len: usize,
    epoch: u64,
    locations: ?[]u8 = null,
    exclusions: ?[]u8 = null,
    found: files.List = .{},
    ok: bool = false,

    fn run(a: *FileAsk) void {
        const q = a.text[0..a.len];
        if (files.isPath(q)) {
            files.complete(a.live.app.io, q, &a.found);
            a.ok = true;
        } else a.ok = files.find(a.live.app.io, q, a.locations orelse "", a.exclusions orelse "", &a.found);
        if (a.ok) a.found.icons();
        nanoui.App.after(0, a, done);
    }

    fn done(ctx: ?*anyopaque) callconv(.c) void {
        const a: *FileAsk = @ptrCast(@alignCast(ctx.?));
        const l = a.live;
        defer a.destroy();
        l.files.busy = false;
        if (a.ok and a.epoch == l.files.epoch) {
            l.s.filesAnswered(a.text[0..a.len], &a.found);
            if (l.window) |w| w.redraw();
        }
        sendFiles(l);
    }

    fn destroy(a: *FileAsk) void {
        const gpa = a.live.app.gpa;
        if (a.locations) |v| gpa.free(v);
        if (a.exclusions) |v| gpa.free(v);
        a.found.deinit();
        gpa.destroy(a);
    }
};

pub const State = struct {
    query: [files.max_path]u8 = undefined,
    len: usize = 0,
    waiting: u32 = 0,
    epoch: u64 = 0,
    sent: u64 = 0,
    busy: bool = false,
};

pub fn load(l: *Live) void {
    // File search is local to this Mac and off unless explicitly enabled.
    if (mac) if (l.kv.get(l.app.gpa, files.enabled_key) catch null) |v| {
        defer l.app.gpa.free(v);
        l.s.files_on = std.mem.eql(u8, v, "1");
    };
}

/// Google is asked once typing pauses (`suggest.pause_ms`).
pub fn ask(ctx: *anyopaque, query: []const u8) void {
    const l: *Live = @ptrCast(@alignCast(ctx));
    const q = std.mem.trim(u8, query, " ");
    if (q.len > suggest.max_len) return;
    @memcpy(l.asking[0..q.len], q);
    l.asking_len = q.len;
    l.waiting += 1;
    nanoui.App.after(suggest.pause_ms, l, struct {
        fn f(c: ?*anyopaque) callconv(.c) void {
            const live: *Live = @ptrCast(@alignCast(c.?));
            live.waiting -= 1;
            if (live.waiting == 0) sendSuggest(live);
        }
    }.f);
}

fn sendSuggest(l: *Live) void {
    const q = l.asking[0..l.asking_len];
    if (!l.s.suggest_on or !suggest.same(q, l.s.query.text())) return;
    const a = l.app.gpa.create(Ask) catch return l.s.unanswered(q);
    a.* = .{ .live = l, .len = q.len };
    @memcpy(a.text[0..q.len], q);
    var buf: [512]u8 = undefined;
    nanoui.http.fetch(l.app.gpa, .{
        .url = suggest.url(&buf, q),
        .headers = &.{.{ .name = "Accept", .value = "application/json" }},
        .timeout = 4,
    }, a, Ask.done);
}

/// Currency is asked once typing pauses, as Google's completions are.
pub fn askRates(ctx: *anyopaque, amount: f64, from: []const u8, to: []const u8) void {
    const l: *Live = @ptrCast(@alignCast(ctx));
    if (from.len != 3 or to.len != 3) return;
    const job = l.app.gpa.create(AskRates) catch return l.s.ratesFailed(amount, from, to);
    job.* = .{ .live = l, .amount = amount };
    @memcpy(job.from[0..3], from[0..3]);
    @memcpy(job.to[0..3], to[0..3]);
    nanoui.App.after(@import("currency.zig").pause_ms, job, struct {
        fn f(c: ?*anyopaque) callconv(.c) void {
            const pending: *AskRates = @ptrCast(@alignCast(c.?));
            pending.send();
        }
    }.f);
}

const Ask = struct {
    live: *Live,
    text: [suggest.max_len]u8 = undefined,
    len: usize,

    fn done(a: *Ask, r: nanoui.http.Response) void {
        const l = a.live;
        defer l.app.gpa.destroy(a);
        defer if (l.window) |w| w.redraw();
        var arena: std.heap.ArenaAllocator = .init(l.app.gpa);
        defer arena.deinit();
        var list: suggest.List = .{};
        if (r.status != 200 or !suggest.decode(arena.allocator(), r.body, a.text[0..a.len], &list)) return l.s.unanswered(a.text[0..a.len]);
        l.s.answered(a.text[0..a.len], &list);
    }
};

const AskRates = struct {
    live: *Live,
    amount: f64,
    from: [3]u8 = undefined,
    to: [3]u8 = undefined,

    fn send(a: *AskRates) void {
        const l = a.live;
        const currency = @import("currency.zig");
        const q = currency.parse(l.s.query.text()) orelse {
            l.app.gpa.destroy(a);
            return;
        };
        if (q.amount != a.amount or !std.mem.eql(u8, q.fromSlice(), a.from[0..3]) or !std.mem.eql(u8, q.toSlice(), a.to[0..3])) {
            l.app.gpa.destroy(a);
            return;
        }
        var buf: [256]u8 = undefined;
        const u = currency.url(&buf, a.amount, a.from[0..3], a.to[0..3]);
        if (u.len == 0) {
            l.app.gpa.destroy(a);
            return l.s.ratesFailed(a.amount, a.from[0..3], a.to[0..3]);
        }
        nanoui.http.fetch(l.app.gpa, .{
            .url = u,
            .headers = &.{.{ .name = "Accept", .value = "application/json" }},
            .timeout = 6,
        }, a, AskRates.done);
    }

    fn done(a: *AskRates, r: nanoui.http.Response) void {
        const l = a.live;
        defer l.app.gpa.destroy(a);
        defer if (l.window) |w| w.redraw();
        const currency = @import("currency.zig");
        var ans: currency.Answer = .{};
        if (r.status != 200 or !currency.decode(r.body, .{ .amount = a.amount, .from = a.from, .to = a.to }, &ans)) {
            return l.s.ratesFailed(a.amount, a.from[0..3], a.to[0..3]);
        }
        l.s.ratesAnswered(a.amount, a.from[0..3], a.to[0..3], ans);
    }
};
