//! Nanolight's optional Island / Notch mode: pairs Nanolight's launcher with
//! a rich Now Playing music player (synced lyrics, Up Next queue, interactive
//! timeline & volume, shuffle/repeat, and macOS MediaRemote integration),
//! a Pomodoro Focus Timer with Keep Awake, Smart Clipboard history, and
//! Scratchpad Notes.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

pub const enabled_key = "nanolight.island";
pub const notes_key = "nanolight.notes";

pub const compact_width: f32 = 284;
pub const compact_height: f32 = 38;
pub const bar_height: f32 = 40;

pub const Tab = enum {
    search,
    music,
    focus,
    shelf,

    pub const all = [_]Tab{ .search, .music, .focus, .shelf };

    pub fn title(t: Tab) []const u8 {
        return switch (t) {
            .search => "Search",
            .music => "Music",
            .focus => "Focus",
            .shelf => "Shelf",
        };
    }

    pub fn icon(t: Tab) []const u8 {
        return switch (t) {
            .search => "magnifyingglass",
            .music => "music.note",
            .focus => "flame",
            .shelf => "doc.on.doc",
        };
    }
};

pub const LyricLine = struct {
    at_s: u32,
    text: []const u8,
};

pub const Track = struct {
    title: []const u8,
    artist: []const u8,
    album: []const u8,
    app: []const u8,
    quality: []const u8,
    duration_s: u32,
    accent: u24,
    lyrics: [4]LyricLine,
};

pub const catalog = [_]Track{
    .{
        .title = "Midnight City Lights",
        .artist = "The Night Drivers",
        .album = "After Hours",
        .app = "Music",
        .quality = "Lossless · 24-bit/96kHz",
        .duration_s = 243,
        .accent = 0x4aa8ff,
        .lyrics = .{
            .{ .at_s = 0, .text = "Neon reflections on the wet boulevard" },
            .{ .at_s = 60, .text = "And every light was calling out your name" },
            .{ .at_s = 120, .text = "Chasing horizons till the sky turns gold" },
            .{ .at_s = 180, .text = "Stay in the frequency until the dawn" },
        },
    },
    .{
        .title = "Solar Echoes",
        .artist = "Lumen & Glass",
        .album = "Prismatic",
        .app = "Music",
        .quality = "Lossless · ALAC",
        .duration_s = 214,
        .accent = 0xff9f43,
        .lyrics = .{
            .{ .at_s = 0, .text = "Golden static drifting through the pines" },
            .{ .at_s = 50, .text = "We traced the skyline through the summer rain" },
            .{ .at_s = 110, .text = "Every echo bends the light in two" },
            .{ .at_s = 165, .text = "Fading softly into amber waves" },
        },
    },
    .{
        .title = "Velvet Horizon",
        .artist = "Kora & The Analogues",
        .album = "Tape Loops Vol. 4",
        .app = "Spotify",
        .quality = "Very High · 320kbps",
        .duration_s = 198,
        .accent = 0xa56eff,
        .lyrics = .{
            .{ .at_s = 0, .text = "Warm tape hiss and a Rhodes chord" },
            .{ .at_s = 45, .text = "Drifting past the midnight harbour lights" },
            .{ .at_s = 95, .text = "Hold the tempo steady in the dark" },
            .{ .at_s = 150, .text = "Until the morning clears the bay" },
        },
    },
    .{
        .title = "Kyoto Rain",
        .artist = "Haruka Sato",
        .album = "Quiet Stations",
        .app = "Music",
        .quality = "Hi-Res Lossless",
        .duration_s = 268,
        .accent = 0x3ddbd9,
        .lyrics = .{
            .{ .at_s = 0, .text = "Raindrops on the cedar temple eaves" },
            .{ .at_s = 65, .text = "Lanterns glowing along the stone path" },
            .{ .at_s = 135, .text = "A distant train bell across the river" },
            .{ .at_s = 200, .text = "Stillness settles over the garden" },
        },
    },
};

pub const RepeatMode = enum {
    off,
    all,
    one,

    pub fn next(r: RepeatMode) RepeatMode {
        return switch (r) {
            .off => .all,
            .all => .one,
            .one => .off,
        };
    }

    pub fn label(r: RepeatMode) []const u8 {
        return switch (r) {
            .off => "Off",
            .all => "All",
            .one => "1",
        };
    }
};

pub const MusicPane = enum { lyrics, queue };

pub const NowPlaying = struct {
    track_idx: usize = 0,
    custom_active: bool = false,
    title_buf: [96]u8 = undefined,
    title_len: u8 = 0,
    artist_buf: [64]u8 = undefined,
    artist_len: u8 = 0,
    app_buf: [32]u8 = undefined,
    app_len: u8 = 0,
    lyric_buf: [128]u8 = undefined,
    lyric_len: u8 = 0,
    playing: bool = false,
    elapsed_s: u32 = 88,
    duration_s: u32 = 243,
    shuffle: bool = false,
    repeat: RepeatMode = .off,
    liked: [catalog.len]bool = .{ true, false, false, false },
    volume: u8 = 75,
    muted: bool = false,
    pane: MusicPane = .lyrics,
    live_media: bool = false,

    pub fn initDefault() NowPlaying {
        return .{};
    }

    pub fn currentTrack(np: *const NowPlaying) Track {
        return catalog[np.track_idx % catalog.len];
    }

    pub fn setTrack(np: *NowPlaying, t: []const u8, a: []const u8, app_name: []const u8) void {
        np.custom_active = true;
        const tl = @min(t.len, np.title_buf.len);
        @memcpy(np.title_buf[0..tl], t[0..tl]);
        np.title_len = @intCast(tl);
        const al = @min(a.len, np.artist_buf.len);
        @memcpy(np.artist_buf[0..al], a[0..al]);
        np.artist_len = @intCast(al);
        const pl = @min(app_name.len, np.app_buf.len);
        @memcpy(np.app_buf[0..pl], app_name[0..pl]);
        np.app_len = @intCast(pl);
    }

    pub fn setLyric(np: *NowPlaying, line: []const u8) void {
        np.custom_active = true;
        const l = @min(line.len, np.lyric_buf.len);
        @memcpy(np.lyric_buf[0..l], line[0..l]);
        np.lyric_len = @intCast(l);
    }

    pub fn title(np: *const NowPlaying) []const u8 {
        if (np.custom_active and np.title_len > 0) return np.title_buf[0..np.title_len];
        return np.currentTrack().title;
    }

    pub fn artist(np: *const NowPlaying) []const u8 {
        if (np.custom_active and np.artist_len > 0) return np.artist_buf[0..np.artist_len];
        return np.currentTrack().artist;
    }

    pub fn album(np: *const NowPlaying) []const u8 {
        return np.currentTrack().album;
    }

    pub fn appName(np: *const NowPlaying) []const u8 {
        if (np.custom_active and np.app_len > 0) return np.app_buf[0..np.app_len];
        return np.currentTrack().app;
    }

    pub fn quality(np: *const NowPlaying) []const u8 {
        return np.currentTrack().quality;
    }

    pub fn accent(np: *const NowPlaying) u24 {
        return np.currentTrack().accent;
    }

    pub fn activeLyricIndex(np: *const NowPlaying) usize {
        const lines = np.currentTrack().lyrics;
        var idx: usize = 0;
        for (lines, 0..) |line, i| {
            if (np.elapsed_s >= line.at_s) idx = i;
        }
        return idx;
    }

    pub fn lyric(np: *const NowPlaying) []const u8 {
        if (np.custom_active and np.lyric_len > 0) return np.lyric_buf[0..np.lyric_len];
        const lines = np.currentTrack().lyrics;
        return lines[np.activeLyricIndex()].text;
    }

    pub fn toggle(np: *NowPlaying) void {
        np.playing = !np.playing;
        if (np.live_media) sendMediaCommand(2); // kMRTogglePlayPause
    }

    pub fn selectTrack(np: *NowPlaying, idx: usize) void {
        np.custom_active = false;
        np.track_idx = idx % catalog.len;
        np.duration_s = catalog[np.track_idx].duration_s;
        np.elapsed_s = 0;
        np.playing = true;
    }

    pub fn skip(np: *NowPlaying, next: bool) void {
        if (np.live_media) sendMediaCommand(if (next) 4 else 5); // kMRNextTrack / kMRPreviousTrack
        if (!next and np.elapsed_s > 10) {
            np.elapsed_s = 0;
            return;
        }
        if (np.repeat == .one) {
            np.elapsed_s = 0;
            return;
        }
        np.custom_active = false;
        const step: usize = if (np.shuffle) 2 else 1;
        np.track_idx = if (next)
            (np.track_idx + step) % catalog.len
        else
            (np.track_idx + catalog.len - (step % catalog.len)) % catalog.len;
        np.duration_s = catalog[np.track_idx].duration_s;
        np.elapsed_s = 0;
    }

    pub fn seekTo(np: *NowPlaying, sec: u32) void {
        np.elapsed_s = @min(sec, np.duration_s);
    }

    pub fn seekRatio(np: *NowPlaying, ratio: f32) void {
        const clamped = std.math.clamp(ratio, 0, 1);
        np.elapsed_s = @intFromFloat(@round(clamped * @as(f32, @floatFromInt(np.duration_s))));
    }

    pub fn isLiked(np: *const NowPlaying) bool {
        return np.liked[np.track_idx % catalog.len];
    }

    pub fn toggleLiked(np: *NowPlaying) void {
        const i = np.track_idx % catalog.len;
        np.liked[i] = !np.liked[i];
    }

    pub fn setVolume(np: *NowPlaying, pct: u8) void {
        np.volume = @min(pct, 100);
        if (np.volume > 0) np.muted = false;
    }

    pub fn toggleMute(np: *NowPlaying) void {
        np.muted = !np.muted;
    }

    pub fn effectiveVolume(np: *const NowPlaying) u8 {
        return if (np.muted) 0 else np.volume;
    }

    pub fn progress(np: *const NowPlaying) f32 {
        if (np.duration_s == 0) return 0;
        return std.math.clamp(@as(f32, @floatFromInt(np.elapsed_s)) / @as(f32, @floatFromInt(np.duration_s)), 0, 1);
    }
};

/// Sends a system media remote command on macOS (e.g., 2 = TogglePlayPause,
/// 4 = NextTrack, 5 = PreviousTrack) via MediaRemote.framework when present.
fn sendMediaCommand(cmd: u32) void {
    if (comptime builtin.os.tag != .macos) return;
    const lib = std.c.dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", .{ .LAZY = true }) orelse return;
    defer _ = std.c.dlclose(lib);
    const sym = std.c.dlsym(lib, "MRMediaRemoteSendCommand") orelse return;
    const send: *const fn (u32, ?*anyopaque) callconv(.c) bool = @ptrCast(@alignCast(sym));
    _ = send(cmd, null);
}

pub const FocusTimer = struct {
    preset_min: u16 = 25,
    remaining_s: u32 = 25 * 60,
    running: bool = false,
    is_break: bool = false,
    keep_awake: bool = false,

    pub const presets = [_]u16{ 15, 25, 45, 5 };

    pub fn setMinutes(ft: *FocusTimer, min: u16) void {
        ft.preset_min = min;
        ft.remaining_s = @as(u32, min) * 60;
        ft.is_break = (min == 5);
    }

    pub fn toggle(ft: *FocusTimer) void {
        ft.running = !ft.running;
    }

    pub fn reset(ft: *FocusTimer) void {
        ft.running = false;
        ft.remaining_s = @as(u32, ft.preset_min) * 60;
    }

    pub fn formatRemaining(ft: *const FocusTimer, buf: *[16]u8) []const u8 {
        const m = ft.remaining_s / 60;
        const s = ft.remaining_s % 60;
        return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}", .{ m, s }) catch "25:00";
    }
};

pub const ClipKind = enum {
    text,
    link,
    color,

    pub fn classify(s: []const u8) ClipKind {
        const trimmed = std.mem.trim(u8, s, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed, "http://") or std.mem.startsWith(u8, trimmed, "https://")) return .link;
        if (trimmed.len == 7 and trimmed[0] == '#') {
            for (trimmed[1..]) |ch| if (!std.ascii.isHex(ch)) break else return .color;
        }
        return .text;
    }
};

pub const ClipFilter = enum {
    all,
    links,
    colors,
    pinned,

    pub const list = [_]ClipFilter{ .all, .links, .colors, .pinned };

    pub fn title(f: ClipFilter) []const u8 {
        return switch (f) {
            .all => "All",
            .links => "Links",
            .colors => "Colors",
            .pinned => "Pinned",
        };
    }
};

pub const ClipEntry = struct {
    buf: [160]u8 = undefined,
    len: u8 = 0,
    kind: ClipKind = .text,
    pinned: bool = false,

    pub fn slice(e: *const ClipEntry) []const u8 {
        return e.buf[0..e.len];
    }
};

pub const max_clips = 8;

pub const Island = struct {
    /// When `island_on` is true and `collapsed` is true on a notched MacBook,
    /// the window renders only the compact notch pill at the top of the screen.
    collapsed: bool = false,
    tab: Tab = .search,
    hovered: bool = false,
    now_playing: NowPlaying = .initDefault(),
    timer: FocusTimer = .{},
    clips: [max_clips]ClipEntry = undefined,
    clip_count: usize = 0,
    clip_filter: ClipFilter = .all,
    notes: ui.TextBuffer = .{},
    notes_initialized: bool = false,

    pub fn ensureSeeded(isl: *Island) void {
        if (isl.clip_count > 0) return;
        isl.captureClip("https://halo-mac.com/");
        isl.captureClip("#4AA8FF");
        isl.captureClip("zig build test --fork=../..");
        isl.clips[0].pinned = true;
    }

    pub fn deinit(isl: *Island) void {
        isl.notes.deinit();
    }

    pub fn captureClip(isl: *Island, raw: []const u8) void {
        const text = std.mem.trim(u8, raw, " \t\r\n");
        if (text.len == 0) return;
        const len: u8 = @intCast(@min(text.len, 160));
        const clipped = text[0..len];
        for (isl.clips[0..isl.clip_count], 0..) |*existing, idx| {
            if (std.mem.eql(u8, existing.slice(), clipped)) {
                const saved = existing.*;
                var k = idx;
                while (k > 0) : (k -= 1) isl.clips[k] = isl.clips[k - 1];
                isl.clips[0] = saved;
                return;
            }
        }
        const limit = @min(isl.clip_count, max_clips - 1);
        var k = limit;
        while (k > 0) : (k -= 1) isl.clips[k] = isl.clips[k - 1];
        var entry: ClipEntry = .{ .len = len, .kind = ClipKind.classify(clipped), .pinned = false };
        @memcpy(entry.buf[0..len], clipped);
        isl.clips[0] = entry;
        if (isl.clip_count < max_clips) isl.clip_count += 1;
    }

    pub fn togglePin(isl: *Island, idx: usize) void {
        if (idx >= isl.clip_count) return;
        isl.clips[idx].pinned = !isl.clips[idx].pinned;
    }

    pub fn matchesFilter(entry: *const ClipEntry, f: ClipFilter) bool {
        return switch (f) {
            .all => true,
            .links => entry.kind == .link,
            .colors => entry.kind == .color,
            .pinned => entry.pinned,
        };
    }
};

pub fn loadEnabled(kv: nanoui.kv.Store, gpa: std.mem.Allocator) bool {
    const v = kv.get(gpa, enabled_key) catch null orelse return false;
    defer gpa.free(v);
    return std.mem.eql(u8, v, "1");
}

pub fn loadNotes(isl: *Island, kv: nanoui.kv.Store, gpa: std.mem.Allocator) void {
    isl.notes_initialized = true;
    const v = kv.get(gpa, notes_key) catch null orelse return;
    defer gpa.free(v);
    isl.notes.set(v);
}

pub fn saveNotes(isl: *const Island, kv: ?nanoui.kv.Store) void {
    const store = kv orelse return;
    store.set(notes_key, isl.notes.text()) catch {};
}

test "island: music queue, seeking, lyrics, focus timer, and smart clipboard" {
    var isl: Island = .{};
    defer isl.deinit();
    isl.ensureSeeded();
    try std.testing.expectEqual(@as(usize, 3), isl.clip_count);

    // Music seeking & synced lyric progression
    try std.testing.expectEqualStrings("Midnight City Lights", isl.now_playing.title());
    isl.now_playing.seekTo(130);
    try std.testing.expectEqual(@as(usize, 2), isl.now_playing.activeLyricIndex());
    try std.testing.expectEqualStrings("Chasing horizons till the sky turns gold", isl.now_playing.lyric());

    // Selecting next track in catalog
    isl.now_playing.skip(true);
    try std.testing.expectEqualStrings("Solar Echoes", isl.now_playing.title());
    try std.testing.expectEqual(@as(u32, 0), isl.now_playing.elapsed_s);

    // Volume & mute
    isl.now_playing.setVolume(60);
    try std.testing.expectEqual(@as(u8, 60), isl.now_playing.effectiveVolume());
    isl.now_playing.toggleMute();
    try std.testing.expectEqual(@as(u8, 0), isl.now_playing.effectiveVolume());

    // Focus timer preset
    isl.timer.setMinutes(15);
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("15:00", isl.timer.formatRemaining(&buf));
}
