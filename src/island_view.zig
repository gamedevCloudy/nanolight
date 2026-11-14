//! The Island views in Nanolight: the closed compact notch pill (on notched
//! MacBooks), the header chips, and the Music (Now Playing, synced lyrics,
//! Up Next queue, interactive scrubber & volume), Focus (Pomodoro timer &
//! Keep Awake), and Shelf (Smart Clipboard & Scratchpad Note) views.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const panel = @import("view.zig");
const island = @import("island.zig");
const Palette = panel.Palette;

pub const expanded_height: f32 = panel.rows_height;

/// Closed Dynamic Island pill at the top center of the window (only used on
/// MacBooks with a physical notch).
pub fn compact(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    const isl = &s.island;
    const np = &isl.now_playing;
    isl.ensureSeeded();
    _ = s.follow(island.compact_height);
    const row = ui.div(c).row().w(panel.width).h(island.compact_height).center();
    defer row.end();

    const accent = ui.Color.hex(np.accent());
    ui.key(c, "island-compact-pill");
    const pill = ui.div(c).row().w(island.compact_width).h(island.compact_height).px(12).gap(8).itemsCenter()
        .rounded(18).bg(ui.Color.hex(0x000000)).border(p.hair.alpha(0.35)).control();
    if (pill.clicked()) {
        isl.collapsed = false;
        isl.tab = .music;
    }

    // Left wing: Album badge in the track's accent hue
    const art = ui.div(c).size(22, 22).rounded(6).bg(accent.alpha(0.28)).center();
    ui.icon(c, if (np.playing) "play.fill" else "music.note", .{
        .size = 11,
        .weight = .semibold,
        .color = accent,
    });
    art.end();

    ui.text(c, np.title(), .{ .size = 12, .weight = .medium, .color = ui.Color.white.alpha(0.92), .truncate = .ellipsis });
    ui.spacer(c);

    // Right wing: timer countdown or equalizer bars
    var tbuf: [16]u8 = undefined;
    if (isl.timer.running) {
        ui.text(c, c.print("{s}", .{isl.timer.formatRemaining(&tbuf)}), .{ .size = 11.5, .weight = .semibold, .color = ui.Color.hex(0xffbe55), .tabular = true });
    } else {
        equalizer(c, np.playing, accent);
    }
    pill.end();
}

fn equalizer(c: *ui.Context, active: bool, accent: ui.Color) void {
    const col = if (active) accent else ui.Color.white.alpha(0.32);
    const bars = ui.div(c).row().gap(2).itemsCenter().h(14);
    defer bars.end();
    const hs: [4]f32 = if (active) .{ 7, 13, 9, 11 } else .{ 4, 4, 4, 4 };
    for (hs) |bh| ui.div(c).w(2.5).h(bh).roundedFull().bg(col).end();
}

/// Compact chips shown on the right side of the main search header bar.
pub fn headerChips(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    const isl = &s.island;
    const np = &isl.now_playing;
    isl.ensureSeeded();
    const strip = ui.div(c).row().gap(4).itemsCenter();
    defer strip.end();

    const accent = ui.Color.hex(np.accent());
    for ([_]island.Tab{ .music, .focus, .shelf }) |t| {
        ui.key(c, c.print("island-chip-{s}", .{@tagName(t)}));
        const active_music = (t == .music and np.playing);
        const b = ui.div(c).row().h(26).px(8).gap(5).itemsCenter().rounded(7)
            .bg(if (active_music) accent.alpha(0.18) else p.tile.alpha(0.65)).hover(p.sel).control();
        if (b.clicked()) isl.tab = t;
        ui.icon(c, t.icon(), .{ .size = 11, .weight = .medium, .color = if (active_music) accent else p.sub });
        ui.text(c, t.title(), .{ .size = 11.5, .weight = .medium, .color = if (active_music) p.text else p.sub });
        b.end();
    }
}

/// Top navigation bar inside the expanded `Music`, `Focus`, or `Shelf` view.
pub fn bar(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    const isl = &s.island;
    const np = &isl.now_playing;
    isl.ensureSeeded();
    const strip = ui.div(c).row().wFull().h(island.bar_height).px(14).gap(6).itemsCenter();
    defer strip.end();

    // Mini Now Playing indicator on the left
    const accent = ui.Color.hex(np.accent());
    const badge = ui.div(c).row().h(26).px(8).gap(6).itemsCenter().rounded(8).bg(accent.alpha(0.16)).control();
    if (badge.clicked()) isl.tab = .music;
    equalizer(c, np.playing, accent);
    ui.text(c, np.title(), .{ .size = 11.5, .weight = .medium, .color = p.text.alpha(0.9), .truncate = .ellipsis });
    badge.end();

    ui.spacer(c);

    // Tab pills
    for (island.Tab.all) |t| {
        ui.key(c, c.print("island-tab-{s}", .{@tagName(t)}));
        const on = isl.tab == t;
        const b = ui.div(c).row().h(28).px(10).gap(5).itemsCenter().rounded(8).control()
            .bg(if (on) p.sel else p.fill.alpha(0)).border(if (on) p.rim else p.fill.alpha(0));
        if (b.clicked()) {
            isl.tab = t;
            if (t == .search) s.query.focus();
        }
        ui.icon(c, t.icon(), .{ .size = 11.5, .weight = .medium, .color = if (on) p.text else p.sub });
        ui.text(c, t.title(), .{ .size = 12, .weight = if (on) .semibold else .medium, .color = if (on) p.text else p.sub });
        b.end();
    }

    ui.spacer(c);

    var tbuf: [16]u8 = undefined;
    ui.text(c, c.print("{s}", .{isl.timer.formatRemaining(&tbuf)}), .{
        .size = 11.5,
        .weight = .medium,
        .color = if (isl.timer.running) ui.Color.hex(0xffbe55) else p.sub.alpha(0.75),
        .tabular = true,
    });
    if (s.notchActive()) {
        ui.key(c, "island-collapse");
        const col_btn = ui.div(c).size(26, 26).rounded(7).center().control().hover(p.sel);
        if (col_btn.clicked()) isl.collapsed = true;
        ui.icon(c, "chevron.up", .{ .size = 12, .weight = .medium, .color = p.sub });
        col_btn.end();
    }
}

/// Draws the non-search Island tab (`Music`, `Focus`, or `Shelf`).
pub fn inPanel(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    const isl = &s.island;
    isl.ensureSeeded();
    if (!isl.notes_initialized) {
        if (s.kv) |kv| island.loadNotes(isl, kv, std.heap.page_allocator);
    }
    const S = ui.Shortcut;
    if (c.shortcut(.{ .key = S.escape })) {
        isl.tab = .search;
        s.query.focus();
        return;
    }
    const h = s.follow(expanded_height);
    const box = ui.div(c).column().wFull().h(h).clip();
    defer box.end();
    bar(s, c, p);
    ui.div(c).wFull().h(1).bg(p.hair).end();
    const content_h = h - island.bar_height - panel.footer_h - 2;
    const body = ui.div(c).column().wFull().h(content_h).p(14).gap(10).clip();
    switch (isl.tab) {
        .search => {},
        .music => drawMusic(s, c, p),
        .focus => drawFocus(s, c, p),
        .shelf => drawShelf(s, c, p),
    }
    body.end();
    foot(s, c, p);
}

fn drawMusic(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    const np = &s.island.now_playing;
    const accent = ui.Color.hex(np.accent());

    // Hero Player Card: Artwork, Track Info, Favorite & Volume, Scrubber, Transport
    const hero = ui.div(c).column().wFull().p(14).gap(10).rounded(14).bg(p.tile.alpha(0.55)).border(p.rim);
    {
        // Top row: Artwork disc + Track metadata + Favorite + Volume stepper
        const top = ui.div(c).row().wFull().gap(12).itemsCenter();
        const art = ui.div(c).size(56, 56).rounded(12).bg(accent.alpha(0.22)).border(accent.alpha(0.45)).center();
        const inner_disc = ui.div(c).size(34, 34).roundedFull().bg(accent.alpha(0.32)).center();
        ui.icon(c, if (np.playing) "play.fill" else "music.note", .{ .size = 16, .color = accent });
        inner_disc.end();
        art.end();

        const meta = ui.div(c).column().gap(2).grow();
        ui.text(c, np.title(), .{ .size = 15.5, .weight = .semibold, .color = p.text, .truncate = .ellipsis });
        ui.textf(c, .{ .size = 12.5, .color = p.sub, .truncate = .ellipsis }, "{s} — {s}", .{ np.artist(), np.album() });
        const badge_row = ui.div(c).row().gap(6).itemsCenter();
        const app_chip = ui.div(c).row().h(18).px(6).itemsCenter().rounded(5).bg(accent.alpha(0.18));
        ui.text(c, np.appName(), .{ .size = 10.5, .weight = .semibold, .color = accent });
        app_chip.end();
        ui.text(c, np.quality(), .{ .size = 11, .color = p.sub.alpha(0.8) });
        badge_row.end();
        meta.end();

        // Like / Favorite button
        ui.key(c, "np-like");
        const like_btn = ui.div(c).size(28, 28).rounded(8).bg(p.tile).center().control();
        if (like_btn.clicked()) np.toggleLiked();
        ui.icon(c, if (np.isLiked()) "star.fill" else "star", .{
            .size = 13,
            .color = if (np.isLiked()) ui.Color.hex(0xffbe55) else p.sub,
        });
        like_btn.end();

        // Interactive Volume control (speaker mute + 5 volume bars)
        drawVolume(c, p, np, accent);
        top.end();

        // Interactive Timeline Scrubber (10 clickable segments across the track)
        drawScrubber(c, p, np, accent);

        // Transport Controls + Lyrics/Queue pane switcher
        const ctrl = ui.div(c).row().wFull().gap(6).itemsCenter();
        ui.key(c, "np-shuffle");
        const shuf = ui.div(c).row().h(28).px(8).gap(4).itemsCenter().rounded(7).control()
            .bg(if (np.shuffle) accent.alpha(0.22) else p.tile);
        if (shuf.clicked()) np.shuffle = !np.shuffle;
        ui.icon(c, "shuffle", .{ .size = 11.5, .color = if (np.shuffle) accent else p.sub });
        ui.text(c, "Shuffle", .{ .size = 11, .weight = .medium, .color = if (np.shuffle) p.text else p.sub });
        shuf.end();

        ui.key(c, "np-prev");
        const prev = ui.div(c).size(28, 28).rounded(7).bg(p.tile).center().control();
        if (prev.clicked()) np.skip(false);
        ui.icon(c, "backward.fill", .{ .size = 11.5, .color = p.text });
        prev.end();

        ui.key(c, "np-toggle");
        const play = ui.div(c).row().h(28).px(14).gap(6).itemsCenter().rounded(8).bg(p.sel).border(p.rim).control();
        if (play.clicked()) np.toggle();
        ui.icon(c, if (np.playing) "pause.fill" else "play.fill", .{ .size = 11.5, .color = p.text });
        ui.text(c, if (np.playing) "Pause" else "Play", .{ .size = 12, .weight = .semibold, .color = p.text });
        play.end();

        ui.key(c, "np-next");
        const next = ui.div(c).size(28, 28).rounded(7).bg(p.tile).center().control();
        if (next.clicked()) np.skip(true);
        ui.icon(c, "forward.fill", .{ .size = 11.5, .color = p.text });
        next.end();

        ui.key(c, "np-repeat");
        const rep = ui.div(c).row().h(28).px(8).gap(4).itemsCenter().rounded(7).control()
            .bg(if (np.repeat != .off) accent.alpha(0.22) else p.tile);
        if (rep.clicked()) np.repeat = np.repeat.next();
        ui.icon(c, "repeat", .{ .size = 11.5, .color = if (np.repeat != .off) accent else p.sub });
        ui.text(c, np.repeat.label(), .{ .size = 11, .weight = .medium, .color = if (np.repeat != .off) p.text else p.sub });
        rep.end();

        ui.spacer(c);

        // Pane switcher: Synced Lyrics vs Up Next Queue
        for ([_]struct { pane: island.MusicPane, label: []const u8 }{
            .{ .pane = .lyrics, .label = "Lyrics" },
            .{ .pane = .queue, .label = "Up Next" },
        }) |item| {
            ui.key(c, c.print("np-pane-{s}", .{@tagName(item.pane)}));
            const on = np.pane == item.pane;
            const chip = ui.div(c).row().h(26).px(10).itemsCenter().rounded(7).control()
                .bg(if (on) p.sel else p.tile).border(if (on) p.rim else p.fill.alpha(0));
            if (chip.clicked()) np.pane = item.pane;
            ui.text(c, item.label, .{ .size = 11.5, .weight = if (on) .semibold else .medium, .color = if (on) p.text else p.sub });
            chip.end();
        }
        ctrl.end();
    }
    hero.end();

    // Bottom Card: Synced Lyrics or Up Next Queue
    if (np.pane == .lyrics) {
        drawLyricsCard(c, p, np, accent);
    } else {
        drawQueueCard(c, p, np);
    }
}

fn drawVolume(c: *ui.Context, p: Palette, np: *island.NowPlaying, accent: ui.Color) void {
    const box = ui.div(c).row().h(28).px(8).gap(4).itemsCenter().rounded(8).bg(p.tile);
    defer box.end();
    ui.key(c, "np-mute");
    const spk = ui.div(c).size(18, 18).center().control();
    if (spk.clicked()) np.toggleMute();
    ui.icon(c, "speaker.wave.2.fill", .{ .size = 11.5, .color = if (np.muted) p.sub.alpha(0.45) else p.text });
    spk.end();

    const eff = np.effectiveVolume();
    for ([_]u8{ 20, 40, 60, 80, 100 }, 0..) |lvl, i| {
        ui.key(c, c.print("np-vol-{d}", .{i}));
        const seg = ui.div(c).w(6).h(14).center().control();
        if (seg.clicked()) np.setVolume(lvl);
        const bar_h: f32 = 6.0 + @as(f32, @floatFromInt(i)) * 2.0;
        ui.div(c).w(3.5).h(bar_h).roundedFull().bg(if (eff >= lvl) accent else p.hair).end();
        seg.end();
    }
}

fn drawScrubber(c: *ui.Context, p: Palette, np: *island.NowPlaying, accent: ui.Color) void {
    const row = ui.div(c).row().wFull().gap(8).itemsCenter();
    defer row.end();
    ui.textf(c, .{ .size = 11, .color = p.sub, .tabular = true }, "{d}:{d:0>2}", .{ np.elapsed_s / 60, np.elapsed_s % 60 });

    const segments = 10;
    const seg_w: f32 = 460.0 / @as(f32, segments);
    const prog = np.progress();
    const track = ui.div(c).row().w(460).h(12).itemsCenter();
    for (0..segments) |i| {
        ui.key(c, c.print("np-scrub-{d}", .{i}));
        const seg_end = (@as(f32, @floatFromInt(i + 1))) / @as(f32, segments);
        const seg_mid = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, segments);
        const filled = prog >= seg_end - 0.05;
        const cell = ui.div(c).w(seg_w).h(12).itemsCenter().control();
        if (cell.clicked()) np.seekRatio(seg_mid);
        ui.div(c).w(seg_w - 1).h(5).roundedFull().bg(if (filled) accent else p.hair).end();
        cell.end();
    }
    track.end();

    const rem = np.duration_s -| np.elapsed_s;
    ui.textf(c, .{ .size = 11, .color = p.sub, .tabular = true }, "-{d}:{d:0>2}", .{ rem / 60, rem % 60 });
}

fn drawLyricsCard(c: *ui.Context, p: Palette, np: *island.NowPlaying, accent: ui.Color) void {
    const card = ui.div(c).column().wFull().p(10).gap(4).rounded(12).bg(p.tile.alpha(0.45)).border(p.rim);
    defer card.end();
    const lines = np.currentTrack().lyrics;
    const active_idx = np.activeLyricIndex();
    for (lines, 0..) |line, idx| {
        ui.key(c, c.print("np-lyric-{d}", .{idx}));
        const active = idx == active_idx;
        const r = ui.div(c).row().wFull().h(26).px(8).gap(8).itemsCenter().rounded(7).control()
            .bg(if (active) accent.alpha(0.16) else p.fill.alpha(0)).hover(p.sel);
        if (r.clicked()) np.seekTo(line.at_s);
        ui.textf(c, .{ .size = 10.5, .color = if (active) accent else p.sub.alpha(0.65), .tabular = true }, "{d}:{d:0>2}", .{ line.at_s / 60, line.at_s % 60 });
        ui.text(c, line.text, .{
            .size = if (active) 13 else 12,
            .weight = if (active) .semibold else .medium,
            .color = if (active) p.text else p.sub.alpha(0.75),
            .truncate = .ellipsis,
        });
        r.end();
    }
}

fn drawQueueCard(c: *ui.Context, p: Palette, np: *island.NowPlaying) void {
    const card = ui.div(c).column().wFull().p(8).gap(4).rounded(12).bg(p.tile.alpha(0.45)).border(p.rim);
    defer card.end();
    for (island.catalog, 0..) |tr, idx| {
        ui.key(c, c.print("np-queue-{d}", .{idx}));
        const current = (np.track_idx % island.catalog.len) == idx;
        const tr_col = ui.Color.hex(tr.accent);
        const r = ui.div(c).row().wFull().h(28).px(8).gap(8).itemsCenter().rounded(7).control()
            .bg(if (current) p.sel else p.fill.alpha(0)).hover(p.sel);
        if (r.clicked()) np.selectTrack(idx);
        ui.div(c).size(10, 10).roundedFull().bg(tr_col).end();
        ui.text(c, tr.title, .{ .size = 12.5, .weight = if (current) .semibold else .medium, .color = p.text });
        ui.textf(c, .{ .size = 11.5, .color = p.sub }, "· {s}", .{tr.artist});
        ui.spacer(c);
        if (current) ui.text(c, "Playing", .{ .size = 10.5, .weight = .semibold, .color = tr_col });
        ui.textf(c, .{ .size = 11, .color = p.sub, .tabular = true }, "{d}:{d:0>2}", .{ tr.duration_s / 60, tr.duration_s % 60 });
        r.end();
    }
}

fn drawFocus(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    const ft = &s.island.timer;
    const np = &s.island.now_playing;

    // Focus Timer & Keep Awake Card
    const timer_card = ui.div(c).column().wFull().p(16).gap(14).rounded(14).bg(p.tile.alpha(0.55)).border(p.rim);
    {
        const top = ui.div(c).row().wFull().gap(10).itemsCenter();
        ui.icon(c, "flame", .{ .size = 16, .color = ui.Color.hex(0xffbe55) });
        ui.text(c, if (ft.is_break) "Break Timer" else "Pomodoro Focus Timer", .{ .size = 14.5, .weight = .semibold, .color = p.text });
        ui.spacer(c);
        for (island.FocusTimer.presets) |m| {
            ui.key(c, c.print("timer-preset-{d}", .{m}));
            const on = ft.preset_min == m;
            const chip = ui.div(c).row().h(26).px(10).itemsCenter().rounded(7).control()
                .bg(if (on) p.sel else p.tile).border(if (on) p.rim else p.fill.alpha(0));
            if (chip.clicked()) ft.setMinutes(m);
            ui.textf(c, .{ .size = 11.5, .weight = if (on) .semibold else .medium, .color = if (on) p.text else p.sub }, "{d}m", .{m});
            chip.end();
        }
        top.end();

        const bot = ui.div(c).row().wFull().gap(10).itemsCenter();
        var tbuf: [16]u8 = undefined;
        ui.text(c, c.print("{s}", .{ft.formatRemaining(&tbuf)}), .{ .size = 30, .weight = .bold, .color = p.text, .tabular = true });
        ui.spacer(c);

        ui.key(c, "timer-awake");
        const awake = ui.div(c).row().h(30).px(10).gap(6).itemsCenter().rounded(8).control()
            .bg(if (ft.keep_awake) p.sel else p.tile).border(p.rim);
        if (awake.clicked()) ft.keep_awake = !ft.keep_awake;
        ui.icon(c, "sun.max", .{ .size = 12, .color = if (ft.keep_awake) ui.Color.hex(0xffbe55) else p.sub });
        ui.text(c, if (ft.keep_awake) "Keep Awake: On" else "Keep Awake", .{ .size = 12, .weight = .medium, .color = p.text });
        awake.end();

        ui.key(c, "timer-reset");
        const rst = ui.div(c).row().h(30).px(10).itemsCenter().rounded(8).bg(p.tile).control();
        if (rst.clicked()) ft.reset();
        ui.text(c, "Reset", .{ .size = 12, .weight = .medium, .color = p.sub });
        rst.end();

        ui.key(c, "timer-toggle");
        const start = ui.div(c).row().h(30).px(14).itemsCenter().rounded(8).bg(p.sel).border(p.rim).control();
        if (start.clicked()) ft.toggle();
        ui.text(c, if (ft.running) "Pause Timer" else "Start Focus", .{ .size = 12, .weight = .semibold, .color = p.text });
        start.end();
        bot.end();
    }
    timer_card.end();

    // Companion Soundtrack Strip inside Focus view
    const music_strip = ui.div(c).row().wFull().p(12).gap(10).itemsCenter().rounded(12).bg(p.tile.alpha(0.45)).border(p.rim);
    ui.icon(c, "music.note", .{ .size = 13, .color = ui.Color.hex(np.accent()) });
    ui.textf(c, .{ .size = 12.5, .weight = .medium, .color = p.text }, "{s} · {s}", .{ np.title(), np.artist() });
    ui.spacer(c);
    const open_music = ui.div(c).row().h(26).px(10).itemsCenter().rounded(7).bg(p.tile).control();
    if (open_music.clicked()) s.island.tab = .music;
    ui.text(c, "Open Player", .{ .size = 11.5, .weight = .medium, .color = p.sub });
    open_music.end();
    music_strip.end();
}

fn drawShelf(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    const isl = &s.island;

    // Scratchpad Notes card
    const note_card = ui.div(c).column().wFull().p(12).gap(6).rounded(12).bg(p.tile.alpha(0.55)).border(p.rim);
    {
        const head = ui.div(c).row().wFull().itemsCenter();
        ui.icon(c, "square.and.pencil", .{ .size = 13, .color = p.text });
        ui.div(c).w(6).end();
        ui.text(c, "Scratchpad Note", .{ .size = 13, .weight = .semibold, .color = p.text });
        ui.spacer(c);
        ui.text(c, "Saved automatically", .{ .size = 11, .color = p.sub });
        head.end();

        const before = std.hash.Wyhash.hash(0, isl.notes.text());
        _ = ui.textField(c, &isl.notes, .{
            .bare = true,
            .size = 13.5,
            .width = .fill,
            .placeholder = "Jot a quick note, snippet or reminder…",
            .placeholder_color = p.sub.alpha(0.75),
            .color = p.text,
        });
        if (std.hash.Wyhash.hash(0, isl.notes.text()) != before) island.saveNotes(isl, s.kv);
    }
    note_card.end();

    // Clipboard History header + filter chips
    const clip_head = ui.div(c).row().wFull().gap(6).itemsCenter();
    ui.text(c, "Clipboard History", .{ .size = 12.5, .weight = .semibold, .color = p.sub });
    ui.spacer(c);
    for (island.ClipFilter.list) |f| {
        ui.key(c, c.print("clip-filter-{s}", .{@tagName(f)}));
        const on = isl.clip_filter == f;
        const chip = ui.div(c).row().h(24).px(9).itemsCenter().rounded(7).control()
            .bg(if (on) p.sel else p.tile);
        if (chip.clicked()) isl.clip_filter = f;
        ui.text(c, f.title(), .{ .size = 11, .weight = if (on) .semibold else .medium, .color = if (on) p.text else p.sub });
        chip.end();
    }
    clip_head.end();

    // Clipboard rows (pinned first)
    const list_box = ui.div(c).column().wFull().gap(4);
    defer list_box.end();
    var shown: usize = 0;
    for ([_]bool{ true, false }) |want_pinned| {
        for (isl.clips[0..isl.clip_count], 0..) |*entry, idx| {
            if (entry.pinned != want_pinned) continue;
            if (!island.Island.matchesFilter(entry, isl.clip_filter)) continue;
            if (shown >= 4) break;
            shown += 1;
            clipRow(s, c, p, entry, idx);
        }
    }
}

fn clipRow(s: *panel.Nanolight, c: *ui.Context, p: Palette, entry: *const island.ClipEntry, idx: usize) void {
    ui.key(c, c.print("clip-row-{d}", .{idx}));
    const r = ui.div(c).row().wFull().h(32).px(10).gap(8).itemsCenter().rounded(8).bg(p.tile.alpha(0.45)).control().hover(p.sel);
    defer r.end();
    if (r.clicked()) {
        c.clipboard.write(c.clipboard.ctx, entry.slice());
        s.copied_at = c.time;
    }
    if (entry.kind == .color and entry.len == 7) {
        const rgb = std.fmt.parseInt(u24, entry.slice()[1..7], 16) catch 0x4aa8ff;
        ui.div(c).size(12, 12).roundedFull().bg(ui.Color.hex(rgb)).border(p.rim).end();
    } else {
        ui.icon(c, if (entry.pinned) "star.fill" else "doc.on.doc", .{
            .size = 11.5,
            .color = if (entry.pinned) ui.Color.hex(0xffbe55) else p.sub,
        });
    }
    ui.text(c, entry.slice(), .{ .size = 12.5, .weight = .medium, .color = p.text, .truncate = .ellipsis });
    ui.spacer(c);
    ui.key(c, c.print("clip-pin-{d}", .{idx}));
    const pin = ui.div(c).row().h(22).px(7).itemsCenter().rounded(6).bg(p.tile).control();
    if (pin.clicked()) s.island.togglePin(idx);
    ui.text(c, if (entry.pinned) "Pinned" else "Pin", .{ .size = 10.5, .color = p.sub });
    pin.end();
}

fn foot(s: *panel.Nanolight, c: *ui.Context, p: Palette) void {
    ui.div(c).wFull().h(1).bg(p.hair).end();
    const bar_row = ui.div(c).row().wFull().h(panel.footer_h).px(16).gap(8).itemsCenter();
    defer bar_row.end();
    panel.appIcon(c, 16);
    ui.text(c, "Nanolight", .{ .size = 12, .weight = .medium, .color = p.sub.alpha(0.85) });
    ui.spacer(c);
    ui.key(c, "island-back-search");
    const back = ui.div(c).row().h(26).px(8).gap(6).itemsCenter().rounded(7).control().hover(p.sel);
    if (back.clicked()) {
        s.island.tab = .search;
        s.query.focus();
    }
    ui.text(c, "Back to Search", .{ .size = 12, .color = p.sub.alpha(0.85) });
    ui.kbd(c, "esc");
    back.end();
}
