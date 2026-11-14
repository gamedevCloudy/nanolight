//! The math row and result rows: the expression, an arrow, the answer, or an
//! app/file/search/island row with its tile and matched letters.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const results = @import("results.zig");
const files_view = @import("files_view.zig");
const text = @import("text.zig");
const view = @import("view.zig");
const Nanolight = view.Nanolight;
const Palette = view.Palette;
const Row = results.Row;

const width: f32 = 680;
const list_pad: f32 = 6;
pub const row_h: f32 = 40;
pub const calc_h: f32 = 92;

pub fn draw(c: *ui.Context, p: anytype, query: []const u8, answer: []const u8, hex: []const u8, copied: bool) void {
    const half = (width - list_pad * 2 - 20 - 32 - 24) / 2;
    {
        const l = ui.div(c).column().w(half).itemsCenter().gap(6);
        defer l.end();
        ui.text(c, std.mem.trim(u8, query, " ="), .{ .size = 20, .weight = .medium, .color = p.text.alpha(0.8), .tabular = true });
        chip(c, p, "Expression", null);
    }
    {
        const arrow = ui.div(c).size(32, 32).roundedFull().bg(p.tile).center();
        defer arrow.end();
        ui.icon(c, "arrow.right", .{ .size = 13, .weight = .semibold, .color = p.sub });
    }
    const r = ui.div(c).column().w(half).itemsCenter().gap(6);
    defer r.end();
    ui.text(c, answer, .{ .size = 28, .weight = .semibold, .color = p.text, .tabular = true, .tracking = -0.3 });
    if (copied) {
        c.animationFrame();
        chip(c, p, "Copied", c.theme.success);
    } else chip(c, p, if (hex.len > 0) c.print("Result · {s}", .{hex}) else "Result", null);
}

fn chip(c: *ui.Context, p: anytype, str: []const u8, tone: ?ui.Color) void {
    const d = ui.div(c).row().gap(4).px(8).h(20).itemsCenter().rounded(6).bg(if (tone) |t| t.alpha(0.16) else p.tile);
    defer d.end();
    if (tone) |t| ui.icon(c, "checkmark", .{ .size = 10, .weight = .bold, .color = t });
    ui.text(c, str, .{ .size = 11, .weight = .medium, .color = tone orelse p.sub, .tabular = true });
}

pub fn row(s: *Nanolight, c: *ui.Context, p: Palette, i: usize, r: Row) void {
    const big = r.kind == .calc or r.kind == .currency;
    const d = ui.div(c).row().wFull().h(if (big) calc_h else row_h).px(10).gap(12).itemsCenter().control();
    defer d.end();
    if (i == s.sel) _ = d.rounded(10).bg(p.sel).border(p.rim);
    if (d.clicked()) {
        s.sel = i;
        s.activate(c);
    }
    if (r.kind == .calc or r.kind == .currency) return draw(c, p, s.query.text(), s.res.answer, s.res.hex, c.time - s.copied_at < 1.4);
    tile(s, c, p, r);
    const q = s.query.text();
    switch (r.kind) {
        .calc, .currency => unreachable,
        .app => {
            const a = s.index.apps.items[r.app];
            ui.richText(c, a.name, highlight(s, i, r, p), .{ .size = 13.5, .weight = .medium, .color = p.text.alpha(0.82) });
            ui.text(c, a.folder, .{ .size = 12, .color = p.sub.alpha(0.8) });
        },
        .pane => {
            const pane = @import("settings_panes.zig").all[r.app];
            ui.richText(c, pane.name, highlight(s, i, r, p), .{ .size = 13.5, .weight = .medium, .color = p.text.alpha(0.82) });
            ui.text(c, "System Settings", .{ .size = 12, .color = p.sub.alpha(0.8) });
        },
        .file => files_view.row(s, c, p, i, r),
        .settings => {
            ui.text(c, "Nanolight Settings", .{ .size = 13.5, .weight = .medium, .color = p.text });
            ui.text(c, "Shortcut, sync, updates", .{ .size = 12, .color = p.sub.alpha(0.8) });
        },
        .island => {
            const title_txt = switch (r.web) {
                1 => "Nanolight · Focus Timer",
                2 => "Nanolight · Shelf & Notes",
                else => "Nanolight · Music Player",
            };
            const sub_txt = switch (r.web) {
                1 => "Pomodoro timer & Keep Awake",
                2 => "Clipboard history & scratchpad",
                else => "Now Playing, synced lyrics & queue",
            };
            ui.text(c, title_txt, .{ .size = 13.5, .weight = .medium, .color = p.text });
            ui.text(c, sub_txt, .{ .size = 12, .color = p.sub.alpha(0.8) });
        },
        .suggest => {
            const w = s.web.get(r.web);
            ui.richText(c, w, added(s, i, w, p), .{ .size = 13.5, .color = p.text.alpha(0.72), .truncate = .ellipsis });
        },
        .ask_grok, .ask_claude, .search_x, .search_web => {
            const verb = switch (r.kind) {
                .ask_grok => "Ask Grok",
                .ask_claude => "Ask Claude",
                .search_x => "Search X for",
                else => "Search Google for",
            };
            ui.textf(c, .{ .size = 13.5, .weight = .medium, .color = p.text, .truncate = .ellipsis }, "{s} “{s}”", .{ verb, std.mem.trim(u8, q, " ") });
            ui.text(c, switch (r.kind) {
                .ask_grok => "grok.com",
                .ask_claude => "claude.ai",
                .search_x => "x.com · Latest",
                else => "google.com",
            }, .{ .size = 12, .color = p.sub.alpha(0.8) });
        },
    }
    ui.spacer(c);
    if (i == s.sel) {
        ui.text(c, if (r.kind == .app or r.kind == .file or r.kind == .settings or r.kind == .island or r.kind == .pane) "Open" else "Go", .{ .size = 12, .weight = .medium, .color = p.sub });
        ui.kbd(c, "↩");
    } else if (i < 9) ui.textf(c, .{ .size = 12, .weight = .medium, .color = p.sub.alpha(0.5), .tabular = true }, "{s}{d}", .{ results.mod, i + 1 });
}

fn tile(s: *Nanolight, c: *ui.Context, p: Palette, r: Row) void {
    const app = if (r.kind == .pane) s.index.find("System Settings") else if (r.kind == .app) r.app else null;
    if (app) |a| if (s.index.icon(a)) |png| {
        const box = ui.div(c).size(26, 26).center();
        defer box.end();
        _ = ui.image(c, .{ .key = s.index.apps.items[a].path, .bytes = png, .max_width = 26, .max_height = 26, .radius = 0, .scale = 1 });
        return;
    };
    if (r.kind == .file) return files_view.tile(s, c, p, r);
    const big = r.kind == .calc or r.kind == .currency;
    const side: f32 = if (big) 34 else 26;
    const box = ui.div(c).size(side, side).rounded(if (big) 9 else 7).bg(p.tile).center();
    defer box.end();
    if (r.kind == .search_x) {
        ui.text(c, "𝕏", .{ .size = 15, .weight = .bold, .color = p.text });
        return;
    }
    ui.icon(c, switch (r.kind) {
        .calc, .currency => "plus.forwardslash.minus",
        .ask_grok => "sparkles",
        .island => switch (r.web) {
            1 => "flame",
            2 => "doc.on.doc",
            else => "music.note",
        },
        .ask_claude => "sun.max",
        .search_web => "globe",
        .suggest => "magnifyingglass",
        .settings => "gearshape",
        else => "app.dashed",
    }, .{ .size = if (big) 16 else 13, .weight = .medium, .color = p.text });
}

/// The matched letters, full strength and heavier.
pub fn highlight(s: *Nanolight, i: usize, r: Row, p: Palette) []const ui.Span {
    const hits = r.match.matched();
    var n: usize = 0;
    var k: usize = 0;
    while (k < hits.len and n < s.spans[i].len) {
        var end = k + 1;
        while (end < hits.len and hits[end] == hits[end - 1] + 1) end += 1;
        s.spans[i][n] = .{ .start = hits[k], .end = @as(u32, hits[end - 1]) + 1, .color = p.text, .weight = .semibold };
        n += 1;
        k = end;
    }
    return s.spans[i][0..n];
}

fn added(s: *Nanolight, i: usize, w: []const u8, p: Palette) []const ui.Span {
    const q = std.mem.trim(u8, s.query.text(), " ");
    if (q.len == 0 or w.len <= q.len or !text.utf8StartsWithFold(w, q)) return &.{};
    s.spans[i][0] = .{ .start = @intCast(q.len), .end = @intCast(w.len), .color = p.text, .weight = .semibold };
    return s.spans[i][0..1];
}
