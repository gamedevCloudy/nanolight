//! Tests for Island mode (island.zig, island_view.zig): Settings toggle,
//! compact notch pill vs desktop behavior, Music player (Now Playing, synced
//! lyrics seeking, Up Next queue, shuffle & repeat), Focus Timer, Smart
//! Clipboard & Scratchpad Notes, and launcher search integration.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const Index = @import("apps.zig").Index;
const view = @import("view.zig");
const island = @import("island.zig");
const tests = @import("tests.zig");

test "Notch Island toggles in Settings, collapses on notched Macs, and dismisses cleanly on desktops" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    var mem: nanoui.kv.Memory = .{ .gpa = gpa };
    defer mem.deinit();
    var s: view.Nanolight = .{ .index = &ix, .kv = mem.store() };
    defer s.query.deinit();
    defer s.island.deinit();
    s.reveal();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    t.settle(1);

    try std.testing.expect(!s.island_on);
    try std.testing.expect(!island.loadEnabled(mem.store(), gpa));

    // Open Settings and turn on Notch Island.
    s.openSettings();
    t.settle(1);
    try t.clickText("Notch Island");
    t.settle(1);
    try std.testing.expect(s.island_on);
    try std.testing.expect(island.loadEnabled(mem.store(), gpa));

    // Back to search: compact header chips for Music, Focus, and Shelf are shown.
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(1);
    try std.testing.expect(t.hasText("Music"));
    try std.testing.expect(t.hasText("Focus"));
    try std.testing.expect(t.hasText("Shelf"));

    // Escape on an empty query on a notched MacBook collapses into the notch pill.
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(1);
    try std.testing.expect(s.island.collapsed);
    try std.testing.expectEqual(island.compact_height, s.height());
    try std.testing.expect(t.hasText("Midnight City Lights"));
    if (std.c.getenv("NANOLIGHT_ISLAND_SHOT_DIR")) |dir| {
        var pbuf: [512]u8 = undefined;
        try t.screenshot(try std.fmt.bufPrint(&pbuf, "{s}/island_compact.png", .{std.mem.span(dir)}));
    }

    // Clicking the compact pill opens the Music player.
    try t.clickText("Midnight City Lights");
    t.settle(1);
    try std.testing.expect(!s.island.collapsed);
    try std.testing.expectEqual(island.Tab.music, s.island.tab);

    // Return to search and verify that on a desktop display without a notch
    // (`has_notch = false`), Escape hides the window rather than collapsing.
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(1);
    var probe: tests.Probe = .{};
    s.host = .{ .ctx = &probe, .open = tests.Probe.open, .hide = tests.Probe.hide };
    s.has_notch = false;
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(1);
    try std.testing.expect(!s.island.collapsed);
    try std.testing.expect(probe.hidden);
    try std.testing.expectEqual(view.rows_height, s.height());
}

test "Music tab drives playback, synced lyrics seeking, Up Next queue, shuffle and repeat" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    var s: view.Nanolight = .{ .index = &ix, .island_on = true };
    defer s.query.deinit();
    defer s.island.deinit();
    s.reveal();
    s.island.tab = .music;
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    t.settle(1);

    try std.testing.expect(t.hasText("Midnight City Lights"));
    try std.testing.expect(t.hasText("Lossless · 24-bit/96kHz"));
    try std.testing.expect(!s.island.now_playing.playing);

    // Play & Shuffle
    try t.clickText("Play");
    t.settle(1);
    try std.testing.expect(s.island.now_playing.playing);
    try t.clickText("Shuffle");
    t.settle(1);
    try std.testing.expect(s.island.now_playing.shuffle);

    // Click a synced lyric line to seek to its timestamp (180s).
    try t.clickText("Stay in the frequency until the dawn");
    t.settle(1);
    try std.testing.expectEqual(@as(u32, 180), s.island.now_playing.elapsed_s);
    if (std.c.getenv("NANOLIGHT_ISLAND_SHOT_DIR")) |dir| {
        var pbuf: [512]u8 = undefined;
        try t.screenshot(try std.fmt.bufPrint(&pbuf, "{s}/island_music_lyrics.png", .{std.mem.span(dir)}));
    }

    // Switch to Up Next queue and select "Velvet Horizon".
    try t.clickText("Up Next");
    t.settle(1);
    try std.testing.expectEqual(island.MusicPane.queue, s.island.now_playing.pane);
    try std.testing.expect(t.hasText("Velvet Horizon"));
    try t.clickText("Velvet Horizon");
    t.settle(1);
    try std.testing.expectEqualStrings("Velvet Horizon", s.island.now_playing.title());
    try std.testing.expectEqualStrings("Spotify", s.island.now_playing.appName());
    if (std.c.getenv("NANOLIGHT_ISLAND_SHOT_DIR")) |dir| {
        var pbuf: [512]u8 = undefined;
        try t.screenshot(try std.fmt.bufPrint(&pbuf, "{s}/island_music_queue.png", .{std.mem.span(dir)}));
    }
}

test "Focus tab drives the Pomodoro Focus Timer, Keep Awake, and companion music strip" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    var s: view.Nanolight = .{ .index = &ix, .island_on = true };
    defer s.query.deinit();
    defer s.island.deinit();
    s.reveal();
    s.island.tab = .focus;
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    t.settle(1);

    try t.clickText("15m");
    t.settle(1);
    try std.testing.expectEqual(@as(u32, 15 * 60), s.island.timer.remaining_s);
    try std.testing.expect(t.hasText("15:00"));

    try t.clickText("Start Focus");
    t.settle(1);
    try std.testing.expect(s.island.timer.running);

    try t.clickText("Pause Timer");
    t.settle(1);
    try std.testing.expect(!s.island.timer.running);

    try t.clickText("Keep Awake");
    t.settle(1);
    try std.testing.expect(s.island.timer.keep_awake);
    if (std.c.getenv("NANOLIGHT_ISLAND_SHOT_DIR")) |dir| {
        var pbuf: [512]u8 = undefined;
        try t.screenshot(try std.fmt.bufPrint(&pbuf, "{s}/island_focus.png", .{std.mem.span(dir)}));
    }

    // Companion soundtrack strip opens the Music player.
    try t.clickText("Open Player");
    t.settle(1);
    try std.testing.expectEqual(island.Tab.music, s.island.tab);
}

test "Shelf tab filters clipboard items, copies on click, and saves scratchpad notes" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    var mem: nanoui.kv.Memory = .{ .gpa = gpa };
    defer mem.deinit();
    var s: view.Nanolight = .{ .index = &ix, .island_on = true, .kv = mem.store() };
    defer s.query.deinit();
    defer s.island.deinit();
    s.reveal();
    s.island.tab = .shelf;
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    t.settle(1);

    try std.testing.expect(t.hasText("https://halo-mac.com/"));
    try std.testing.expect(t.hasText("#4AA8FF"));

    try t.clickText("Colors");
    t.settle(1);
    try std.testing.expectEqual(island.ClipFilter.colors, s.island.clip_filter);
    try std.testing.expect(t.hasText("#4AA8FF"));
    try std.testing.expect(!t.hasText("https://halo-mac.com/"));

    try t.clickText("#4AA8FF");
    t.settle(1);
    try std.testing.expectEqualStrings("#4AA8FF", t.clipboard.items);

    try t.clickText("All");
    t.settle(1);
    s.island.notes.focus();
    t.frame();
    tests.press(&t, &.{.{ .insert = "Ship Music Player" }});
    try std.testing.expectEqualStrings("Ship Music Player", s.island.notes.text());

    var fresh: island.Island = .{};
    defer fresh.deinit();
    island.loadNotes(&fresh, mem.store(), gpa);
    try std.testing.expectEqualStrings("Ship Music Player", fresh.notes.text());
}

test "Launcher query matches Music, Focus, and Shelf commands and opens the matching tab" {
    const gpa = std.testing.allocator;
    var ix: Index = .init(gpa);
    defer ix.deinit();
    var s: view.Nanolight = .{ .index = &ix, .island_on = true };
    defer s.query.deinit();
    defer s.island.deinit();
    s.reveal();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&s, view.Nanolight.view), .{ .width = view.width, .height = view.max_height, .dark = true });
    defer t.deinit();
    t.settle(1);

    tests.press(&t, &.{.{ .insert = "music" }});
    try std.testing.expect(t.hasText("Nanolight · Music Player"));
    tests.press(&t, &.{.{ .command = .insert_newline }});
    try std.testing.expectEqual(island.Tab.music, s.island.tab);

    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(1);
    try std.testing.expectEqual(island.Tab.search, s.island.tab);
}
