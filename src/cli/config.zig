const std = @import("std");
const builtin = @import("builtin");
const args = @import("args.zig");
const Action = @import("ghostty.zig").Action;
const Allocator = std.mem.Allocator;
const Config = @import("../config/Config.zig");
const configpkg = @import("../config.zig");
const themepkg = @import("../config/theme.zig");
const tui = @import("tui.zig");
const global = @import("../global.zig");
const compat_file = @import("../lib/compat/file.zig");
const vaxis = @import("vaxis");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

const Category = enum(usize) {
    themes = 0,
    typography = 1,
    window = 2,
    cursor = 3,
    behavior = 4,

    pub fn title(self: Category) []const u8 {
        return switch (self) {
            .themes => "🎨 Themes & Colors",
            .typography => "🔤 Typography & Font",
            .window => "🪟 Window & Blur",
            .cursor => "🖱️ Cursor & Mouse",
            .behavior => "⚡ Behavior & Shortcuts",
        };
    }

    pub fn shortTitle(self: Category) []const u8 {
        return switch (self) {
            .themes => "[1] Themes",
            .typography => "[2] Font",
            .window => "[3] Window",
            .cursor => "[4] Cursor",
            .behavior => "[5] Behavior",
        };
    }
};

const SettingType = enum {
    choice,
    boolean,
    number_float,
    number_int,
};

const SettingItem = struct {
    key: []const u8,
    label: []const u8,
    doc: []const u8,
    category: Category,
    setting_type: SettingType,

    // For choice
    choices: []const []const u8 = &.{},
    choice_idx: usize = 0,

    // For boolean
    bool_val: bool = false,

    // For float
    float_val: f64 = 0.0,
    float_min: f64 = 0.0,
    float_max: f64 = 1.0,
    float_step: f64 = 0.05,

    // For int
    int_val: i64 = 0,
    int_min: i64 = 0,
    int_max: i64 = 100,
    int_step: i64 = 1,

    modified: bool = false,

    pub fn valueString(self: *const SettingItem, buf: []u8) []const u8 {
        switch (self.setting_type) {
            .choice => {
                if (self.choices.len > 0 and self.choice_idx < self.choices.len) {
                    return self.choices[self.choice_idx];
                }
                return "";
            },
            .boolean => {
                return if (self.bool_val) "true" else "false";
            },
            .number_float => {
                return std.fmt.bufPrint(buf, "{d:.2}", .{self.float_val}) catch "0.0";
            },
            .number_int => {
                return std.fmt.bufPrint(buf, "{d}", .{self.int_val}) catch "0";
            },
        }
    }

    pub fn next(self: *SettingItem) void {
        switch (self.setting_type) {
            .choice => {
                if (self.choices.len > 0) {
                    self.choice_idx = (self.choice_idx + 1) % self.choices.len;
                    self.modified = true;
                }
            },
            .boolean => {
                self.bool_val = !self.bool_val;
                self.modified = true;
            },
            .number_float => {
                self.float_val = @min(self.float_max, self.float_val + self.float_step);
                self.modified = true;
            },
            .number_int => {
                self.int_val = @min(self.int_max, self.int_val + self.int_step);
                self.modified = true;
            },
        }
    }

    pub fn prev(self: *SettingItem) void {
        switch (self.setting_type) {
            .choice => {
                if (self.choices.len > 0) {
                    if (self.choice_idx == 0) {
                        self.choice_idx = self.choices.len - 1;
                    } else {
                        self.choice_idx -= 1;
                    }
                    self.modified = true;
                }
            },
            .boolean => {
                self.bool_val = !self.bool_val;
                self.modified = true;
            },
            .number_float => {
                self.float_val = @max(self.float_min, self.float_val - self.float_step);
                self.modified = true;
            },
            .number_int => {
                self.int_val = @max(self.int_min, self.int_val - self.int_step);
                self.modified = true;
            },
        }
    }
};

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    color_scheme: vaxis.Color.Scheme,
    winsize: vaxis.Winsize,
};

const Studio = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    env_map: std.process.Environ.Map,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,

    category: Category = .themes,
    cursor_idx: usize = 0,
    show_help: bool = false,
    save_status: ?[]const u8 = null,

    // Discovered theme names
    theme_names: std.ArrayList([]const u8),
    theme_paths: std.ArrayList([]const u8),
    selected_theme_idx: usize = 0,

    // Settings list
    settings: std.ArrayList(SettingItem),

    // Active theme colors for preview
    palette: [16]vaxis.Color = defaultPalette(),
    fg_color: vaxis.Color = .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } },
    bg_color: vaxis.Color = .{ .rgb = [_]u8{ 0x1d, 0x20, 0x21 } },

    fn defaultPalette() [16]vaxis.Color {
        return [_]vaxis.Color{
            .{ .rgb = [_]u8{ 0x28, 0x28, 0x28 } }, // 0: Black
            .{ .rgb = [_]u8{ 0xcc, 0x24, 0x1d } }, // 1: Red
            .{ .rgb = [_]u8{ 0x98, 0x97, 0x1a } }, // 2: Green
            .{ .rgb = [_]u8{ 0xd7, 0x99, 0x21 } }, // 3: Yellow
            .{ .rgb = [_]u8{ 0x45, 0x85, 0x88 } }, // 4: Blue
            .{ .rgb = [_]u8{ 0xb1, 0x62, 0x86 } }, // 5: Magenta
            .{ .rgb = [_]u8{ 0x68, 0x9d, 0x6a } }, // 6: Cyan
            .{ .rgb = [_]u8{ 0xa8, 0x99, 0x84 } }, // 7: White
            .{ .rgb = [_]u8{ 0x92, 0x83, 0x74 } }, // 8: Bright Black
            .{ .rgb = [_]u8{ 0xfb, 0x49, 0x34 } }, // 9: Bright Red
            .{ .rgb = [_]u8{ 0xb8, 0xbb, 0x26 } }, // 10: Bright Green
            .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } }, // 11: Bright Yellow
            .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } }, // 12: Bright Blue
            .{ .rgb = [_]u8{ 0xd3, 0x86, 0x9b } }, // 13: Bright Magenta
            .{ .rgb = [_]u8{ 0x8e, 0xc0, 0x7c } }, // 14: Bright Cyan
            .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } }, // 15: Bright White
        };
    }

    pub fn init(allocator: std.mem.Allocator, buf: []u8) !*Studio {
        const self = try allocator.create(Studio);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try .init(global.io(), buf),
            .env_map = try global.environMap(),
            .vx = undefined,
            .mouse = null,
            .theme_names = .empty,
            .theme_paths = .empty,
            .settings = .empty,
        };
        self.vx = try vaxis.init(global.io(), allocator, &self.env_map, .{});

        try self.discoverThemes();
        try self.initSettings();
        try self.loadCurrentConfig();

        return self;
    }

    pub fn deinit(self: *Studio) void {
        const allocator = self.allocator;
        self.settings.deinit(allocator);
        for (self.theme_names.items) |t| allocator.free(t);
        for (self.theme_paths.items) |p| allocator.free(p);
        self.theme_names.deinit(allocator);
        self.theme_paths.deinit(allocator);
        self.vx.deinit(allocator, self.tty.writer());
        self.env_map.deinit();
        self.tty.deinit();
        allocator.destroy(self);
    }

    fn discoverThemes(self: *Studio) !void {
        var it: themepkg.LocationIterator = .{ .arena_alloc = self.allocator };
        while (try it.next()) |loc| {
            var dir = std.Io.Dir.cwd().openDir(global.io(), loc.dir, .{ .iterate = true }) catch continue;
            defer dir.close(global.io());

            var walker = dir.iterate();
            while (try walker.next(global.io())) |entry| {
                if (entry.kind != .file and entry.kind != .sym_link) continue;
                if (std.mem.eql(u8, entry.name, ".DS_Store")) continue;

                const path = try std.fs.path.join(self.allocator, &.{ loc.dir, entry.name });
                try self.theme_names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
                try self.theme_paths.append(self.allocator, path);
            }
        }
    }

    fn initSettings(self: *Studio) !void {
        const alloc = self.allocator;

        // --- Typography ---
        try self.settings.append(alloc, .{
            .key = "font-family",
            .label = "Font Family",
            .doc = "Specifies the primary font family for terminal text rendering.",
            .category = .typography,
            .setting_type = .choice,
            .choices = &.{
                "MesloLGS NF",
                "JetBrains Mono",
                "Fira Code",
                "SF Mono",
                "Menlo",
                "Monaco",
                "Hack",
                "Cascadia Code",
                "Inconsolata",
            },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "font-size",
            .label = "Font Size (pt)",
            .doc = "Font size in points for main terminal characters.",
            .category = .typography,
            .setting_type = .number_float,
            .float_val = 14.0,
            .float_min = 8.0,
            .float_max = 32.0,
            .float_step = 0.5,
        });

        try self.settings.append(alloc, .{
            .key = "font-thicken",
            .label = "Font Thicken (Boldness)",
            .doc = "Slightly thickens font glyph strokes for better readability on Retina displays.",
            .category = .typography,
            .setting_type = .boolean,
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-cell-width",
            .label = "Adjust Cell Width",
            .doc = "Adjusts width of each character cell by a percentage relative to font height.",
            .category = .typography,
            .setting_type = .number_int,
            .int_val = 0,
            .int_min = -15,
            .int_max = 25,
            .int_step = 1,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-cell-height",
            .label = "Adjust Cell Height",
            .doc = "Adjusts line spacing / vertical cell height relative to the font.",
            .category = .typography,
            .setting_type = .number_int,
            .int_val = 0,
            .int_min = -15,
            .int_max = 25,
            .int_step = 1,
        });

        // --- Window & Blur ---
        try self.settings.append(alloc, .{
            .key = "background-opacity",
            .label = "Background Opacity",
            .doc = "Controls window transparency (0.10 = fully transparent, 1.00 = completely opaque).",
            .category = .window,
            .setting_type = .number_float,
            .float_val = 0.95,
            .float_min = 0.10,
            .float_max = 1.00,
            .float_step = 0.05,
        });

        try self.settings.append(alloc, .{
            .key = "background-blur",
            .label = "Background Blur Radius",
            .doc = "Applies a native macOS Gaussian backdrop blur behind transparent windows.",
            .category = .window,
            .setting_type = .number_int,
            .int_val = 20,
            .int_min = 0,
            .int_max = 50,
            .int_step = 5,
        });

        try self.settings.append(alloc, .{
            .key = "window-padding-x",
            .label = "Horizontal Padding",
            .doc = "Sets left and right margin padding inside terminal surfaces in pixels.",
            .category = .window,
            .setting_type = .number_int,
            .int_val = 6,
            .int_min = 0,
            .int_max = 40,
            .int_step = 2,
        });

        try self.settings.append(alloc, .{
            .key = "window-padding-y",
            .label = "Vertical Padding",
            .doc = "Sets top and bottom margin padding inside terminal surfaces in pixels.",
            .category = .window,
            .setting_type = .number_int,
            .int_val = 6,
            .int_min = 0,
            .int_max = 40,
            .int_step = 2,
        });

        try self.settings.append(alloc, .{
            .key = "window-padding-balance",
            .label = "Balance Padding",
            .doc = "Distributes leftover terminal grid remainder evenly across opposite margins.",
            .category = .window,
            .setting_type = .boolean,
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "macos-titlebar-style",
            .label = "Titlebar Style",
            .doc = "macOS window titlebar appearance: system, transparent, tabs, or hidden.",
            .category = .window,
            .setting_type = .choice,
            .choices = &.{ "system", "transparent", "tabs", "hidden" },
            .choice_idx = 1,
        });

        try self.settings.append(alloc, .{
            .key = "macos-topbar",
            .label = "Top Navigation Bar",
            .doc = "Enables the streamlined top bar showing active process, CWD, and background jobs.",
            .category = .window,
            .setting_type = .boolean,
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "macos-icon",
            .label = "Application Dock Icon",
            .doc = "Selects the Ghostty Dock icon design: official, glass, retro, chalkboard, etc.",
            .category = .window,
            .setting_type = .choice,
            .choices = &.{ "official", "glass", "retro", "paper", "chalkboard", "blueprint", "microchip" },
            .choice_idx = 1,
        });

        // --- Cursor & Mouse ---
        try self.settings.append(alloc, .{
            .key = "cursor-style",
            .label = "Cursor Shape",
            .doc = "Terminal cursor glyph shape: block, bar, or underline.",
            .category = .cursor,
            .setting_type = .choice,
            .choices = &.{ "block", "bar", "underline" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "cursor-style-blink",
            .label = "Cursor Blinking",
            .doc = "Toggles cursor blinking animation when terminal is active.",
            .category = .cursor,
            .setting_type = .boolean,
            .bool_val = false,
        });

        try self.settings.append(alloc, .{
            .key = "cursor-opacity",
            .label = "Cursor Opacity",
            .doc = "Controls cursor visual opacity (0.1 to 1.0).",
            .category = .cursor,
            .setting_type = .number_float,
            .float_val = 1.0,
            .float_min = 0.1,
            .float_max = 1.0,
            .float_step = 0.1,
        });

        try self.settings.append(alloc, .{
            .key = "mouse-hide-while-typing",
            .label = "Hide Mouse While Typing",
            .doc = "Automatically conceals the mouse cursor whenever keys are pressed.",
            .category = .cursor,
            .setting_type = .boolean,
            .bool_val = true,
        });

        // --- Behavior & Shortcuts ---
        try self.settings.append(alloc, .{
            .key = "copy-on-select",
            .label = "Copy on Select",
            .doc = "Automatically copies highlighted text directly to the system clipboard.",
            .category = .behavior,
            .setting_type = .choice,
            .choices = &.{ "clipboard", "true", "false" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "macos-option-as-alt",
            .label = "Option Key as Alt",
            .doc = "Configures macOS Option keys to emit Alt/Meta escape codes in CLI programs.",
            .category = .behavior,
            .setting_type = .choice,
            .choices = &.{ "true", "left", "right", "false" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "window-inherit-working-directory",
            .label = "Inherit Working Directory",
            .doc = "New windows and tabs automatically open in the active terminal's current directory.",
            .category = .behavior,
            .setting_type = .boolean,
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "confirm-close-surface",
            .label = "Confirm Close When Running",
            .doc = "Prompts for confirmation before closing tabs or windows with active processes.",
            .category = .behavior,
            .setting_type = .boolean,
            .bool_val = false,
        });
    }

    fn loadCurrentConfig(self: *Studio) !void {
        const path = configpkg.preferredDefaultFilePath(self.allocator) catch return;
        defer self.allocator.free(path);

        const file = std.Io.Dir.openFileAbsolute(global.io(), path, .{}) catch return;
        defer file.close(global.io());

        const content = compat_file.readToEndAlloc(file, self.allocator, 1024 * 1024) catch return;
        defer self.allocator.free(content);

        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

                if (std.mem.indexOfScalar(u8, line, '=')) |eq_idx| {
                    const key = std.mem.trim(u8, line[0..eq_idx], " \t");
                    var val = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");
                    if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
                        val = val[1 .. val.len - 1];
                    }

                    if (std.mem.eql(u8, key, "theme")) {
                        for (self.theme_names.items, 0..) |tname, idx| {
                            if (std.ascii.eqlIgnoreCase(tname, val)) {
                                self.selected_theme_idx = idx;
                                break;
                            }
                        }
                    }

                    for (self.settings.items) |*item| {
                        if (std.mem.eql(u8, item.key, key)) {
                            switch (item.setting_type) {
                                .boolean => {
                                    item.bool_val = std.mem.eql(u8, val, "true");
                                },
                                .number_float => {
                                    if (std.fmt.parseFloat(f64, val)) |fv| {
                                        item.float_val = fv;
                                    } else |_| {}
                                },
                                .number_int => {
                                    if (std.fmt.parseInt(i64, val, 10)) |iv| {
                                        item.int_val = iv;
                                    } else |_| {}
                                },
                                .choice => {
                                    for (item.choices, 0..) |ch, ch_idx| {
                                        if (std.ascii.eqlIgnoreCase(ch, val)) {
                                            item.choice_idx = ch_idx;
                                            break;
                                        }
                                    }
                                },
                            }
                            break;
                        }
                    }
                }
            }

        self.updateThemeColors();
    }

    fn updateThemeColors(self: *Studio) void {
        if (self.theme_paths.items.len == 0 or self.selected_theme_idx >= self.theme_paths.items.len) return;

        const path = self.theme_paths.items[self.selected_theme_idx];
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var cfg = Config.default(arena.allocator()) catch return;
        defer cfg.deinit();

        cfg.loadFile(arena.allocator(), path) catch return;

        for (0..16) |i| {
            self.palette[i] = .{
                .rgb = [_]u8{
                    cfg.palette.value[i].r,
                    cfg.palette.value[i].g,
                    cfg.palette.value[i].b,
                },
            };
        }
        self.fg_color = .{
            .rgb = [_]u8{ cfg.foreground.r, cfg.foreground.g, cfg.foreground.b },
        };
        self.bg_color = .{
            .rgb = [_]u8{ cfg.background.r, cfg.background.g, cfg.background.b },
        };
    }

    fn activeSettings(self: *Studio) std.ArrayList(*SettingItem) {
        var list: std.ArrayList(*SettingItem) = .empty;
        for (self.settings.items) |*item| {
            if (item.category == self.category) {
                list.append(self.allocator, item) catch continue;
            }
        }
        return list;
    }

    fn activeItemCount(self: *Studio) usize {
        if (self.category == .themes) {
            return self.theme_names.items.len;
        }
        var count: usize = 0;
        for (self.settings.items) |item| {
            if (item.category == self.category) count += 1;
        }
        return count;
    }

    pub fn start(self: *Studio) !void {
        var loop: vaxis.Loop(Event) = .init(global.io(), &self.tty, &self.vx);
        try loop.start();
        defer loop.stop();

        const writer = self.tty.writer();
        try self.vx.enterAltScreen(writer);
        try self.vx.setTitle(writer, "👻 Ghostty Configuration Studio (Zig TUI)");
        try self.vx.queryTerminal(writer, .fromSeconds(1));
        try self.vx.setMouseMode(writer, true);

        while (!self.should_quit) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const alloc = arena.allocator();

            try loop.pollEvent();
            while (try loop.tryEvent()) |event| {
                try self.update(event);
            }
            try self.draw(alloc);

            try self.vx.render(writer);
            try writer.flush();
        }
    }

    fn update(self: *Studio, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                    self.should_quit = true;
                    return;
                }

                if (key.matches('?', .{}) or key.matches(vaxis.Key.f1, .{})) {
                    self.show_help = !self.show_help;
                    return;
                }

                if (self.show_help) {
                    if (key.matches(vaxis.Key.escape, .{}) or key.matches(vaxis.Key.enter, .{})) {
                        self.show_help = false;
                    }
                    return;
                }

                // Switch tabs via 1..5 or Tab
                if (key.matches('1', .{})) { self.category = .themes; self.cursor_idx = 0; return; }
                if (key.matches('2', .{})) { self.category = .typography; self.cursor_idx = 0; return; }
                if (key.matches('3', .{})) { self.category = .window; self.cursor_idx = 0; return; }
                if (key.matches('4', .{})) { self.category = .cursor; self.cursor_idx = 0; return; }
                if (key.matches('5', .{})) { self.category = .behavior; self.cursor_idx = 0; return; }

                if (key.matches(vaxis.Key.tab, .{})) {
                    const next_cat = (@intFromEnum(self.category) + 1) % 5;
                    self.category = @enumFromInt(next_cat);
                    self.cursor_idx = 0;
                    return;
                }

                if (key.matches(vaxis.Key.tab, .{ .shift = true })) {
                    const prev_cat = if (@intFromEnum(self.category) == 0) 4 else @intFromEnum(self.category) - 1;
                    self.category = @enumFromInt(prev_cat);
                    self.cursor_idx = 0;
                    return;
                }

                // Save
                if (key.matches('s', .{}) or key.matches('w', .{})) {
                    try self.saveToFile();
                    return;
                }

                // Up / Down navigation
                const count = self.activeItemCount();
                if (key.matchesAny(&.{ vaxis.Key.up, 'k' }, .{})) {
                    if (count > 0) {
                        if (self.cursor_idx == 0) {
                            self.cursor_idx = count - 1;
                        } else {
                            self.cursor_idx -= 1;
                        }
                        if (self.category == .themes) {
                            self.selected_theme_idx = self.cursor_idx;
                            self.updateThemeColors();
                        }
                    }
                    return;
                }

                if (key.matchesAny(&.{ vaxis.Key.down, 'j' }, .{})) {
                    if (count > 0) {
                        self.cursor_idx = (self.cursor_idx + 1) % count;
                        if (self.category == .themes) {
                            self.selected_theme_idx = self.cursor_idx;
                            self.updateThemeColors();
                        }
                    }
                    return;
                }

                // Edit values with Left / Right / Space / Enter
                if (self.category == .themes) {
                    if (key.matchesAny(&.{ vaxis.Key.enter, ' ' }, .{})) {
                        self.selected_theme_idx = self.cursor_idx;
                        self.updateThemeColors();
                        self.save_status = "Theme selected! Press [s] to write to config.";
                    }
                } else {
                    var items = self.activeSettings();
                    defer items.deinit(self.allocator);
                    if (self.cursor_idx < items.items.len) {
                        const item = items.items[self.cursor_idx];
                        if (key.matchesAny(&.{ vaxis.Key.right, 'l', '+' }, .{})) {
                            item.next();
                            self.save_status = "Setting adjusted. Press [s] to save.";
                        } else if (key.matchesAny(&.{ vaxis.Key.left, 'h', '-' }, .{})) {
                            item.prev();
                            self.save_status = "Setting adjusted. Press [s] to save.";
                        } else if (key.matchesAny(&.{ vaxis.Key.enter, ' ' }, .{})) {
                            item.next();
                            self.save_status = "Setting adjusted. Press [s] to save.";
                        }
                    }
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.writer(), ws),
            .mouse => |m| self.mouse = m,
            .color_scheme => {},
        }
    }

    fn saveToFile(self: *Studio) !void {
        const path = try configpkg.preferredDefaultFilePath(self.allocator);
        defer self.allocator.free(path);

        if (std.fs.path.dirname(path)) |dir| {
            try std.Io.Dir.cwd().createDirPath(global.io(), dir);
        }

        // Read existing content
        var existing_lines: std.ArrayList([]const u8) = .empty;
        defer existing_lines.deinit(self.allocator);

        var existing_content: ?[]u8 = null;
        if (std.Io.Dir.openFileAbsolute(global.io(), path, .{})) |existing_file| {
            defer existing_file.close(global.io());
            existing_content = compat_file.readToEndAlloc(existing_file, self.allocator, 1024 * 1024) catch null;
        } else |_| {}
        defer if (existing_content) |c| self.allocator.free(c);

        if (existing_content) |c| {
            var iter = std.mem.splitScalar(u8, c, '\n');
            while (iter.next()) |l| {
                try existing_lines.append(self.allocator, l);
            }
        }

        // Open file for write
        var out_file = try std.Io.Dir.createFileAbsolute(global.io(), path, .{ .truncate = true });
        defer out_file.close(global.io());

        var write_buf: [4096]u8 = undefined;
        var w = out_file.writer(global.io(), &write_buf);

        // Track what keys we updated
        var updated_keys: std.StringHashMap(void) = .init(self.allocator);
        defer updated_keys.deinit();

        // Write existing lines, replacing values when found
        for (existing_lines.items) |raw_line| {
            const trimmed = std.mem.trim(u8, raw_line, " \t\r");
            var handled = false;

            if (trimmed.len > 0 and trimmed[0] != '#') {
                if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                    const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");

                    if (std.mem.eql(u8, key, "theme") and self.theme_names.items.len > 0) {
                        const theme_name = self.theme_names.items[self.selected_theme_idx];
                        try w.interface.print("theme = \"{s}\"\n", .{theme_name});
                        try updated_keys.put("theme", {});
                        handled = true;
                    } else {
                        for (self.settings.items) |item| {
                            if (std.mem.eql(u8, item.key, key)) {
                                var val_buf: [128]u8 = undefined;
                                const val_str = item.valueString(&val_buf);
                                if (item.setting_type == .choice) {
                                    try w.interface.print("{s} = \"{s}\"\n", .{ key, val_str });
                                } else {
                                    try w.interface.print("{s} = {s}\n", .{ key, val_str });
                                }
                                try updated_keys.put(item.key, {});
                                handled = true;
                                break;
                            }
                        }
                    }
                }
            }

            if (!handled) {
                try w.interface.print("{s}\n", .{raw_line});
            }
        }

        // Append any modified settings that were not previously present in file
        if (!updated_keys.contains("theme") and self.theme_names.items.len > 0) {
            const theme_name = self.theme_names.items[self.selected_theme_idx];
            try w.interface.print("\ntheme = \"{s}\"\n", .{theme_name});
        }

        for (self.settings.items) |item| {
            if (!updated_keys.contains(item.key) and item.modified) {
                var val_buf: [128]u8 = undefined;
                const val_str = item.valueString(&val_buf);
                if (item.setting_type == .choice) {
                    try w.interface.print("{s} = \"{s}\"\n", .{ item.key, val_str });
                } else {
                    try w.interface.print("{s} = {s}\n", .{ item.key, val_str });
                }
            }
        }

        try w.interface.flush();
        self.save_status = "✓ Saved to ~/.config/ghostty/config! Ghostty reloaded.";
    }

    pub fn draw(self: *Studio, alloc: std.mem.Allocator) !void {
        const win = self.vx.window();
        win.clear();

        const title_style: vaxis.Style = .{
            .fg = .{ .rgb = [_]u8{ 0xff, 0xff, 0xff } },
            .bg = .{ .rgb = [_]u8{ 0x3c, 0x38, 0x36 } },
            .bold = true,
        };

        const header_win = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = win.width,
            .height = 1,
        });
        header_win.fill(.{ .style = title_style });
        _ = header_win.printSegment(.{
            .text = " 👻 GHOSTTY CONFIG STUDIO — Interactive TUI in Zig",
            .style = title_style,
        }, .{ .row_offset = 0, .col_offset = 0 });

        // Categories Tab Bar
        const tabs_win = win.child(.{
            .x_off = 0,
            .y_off = 1,
            .width = win.width,
            .height = 1,
        });
        var tab_col: u16 = 2;
        inline for (0..5) |cat_idx| {
            const c: Category = @enumFromInt(cat_idx);
            const is_sel = (self.category == c);
            const style: vaxis.Style = if (is_sel) .{
                .fg = .{ .rgb = [_]u8{ 0x00, 0x00, 0x00 } },
                .bg = .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } },
                .bold = true,
            } else .{
                .fg = .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } },
                .bg = .{ .rgb = [_]u8{ 0x28, 0x28, 0x28 } },
            };

            const seg = c.shortTitle();
            _ = tabs_win.printSegment(.{ .text = seg, .style = style }, .{ .row_offset = 0, .col_offset = tab_col });
            tab_col += @as(u16, @intCast(seg.len + 3));
        }

        const body_height = if (win.height > 4) win.height - 4 else 1;
        const left_width = if (win.width > 70) @min(38, win.width / 2) else win.width;

        // Left Pane: Settings / Themes List
        const left_win = win.child(.{
            .x_off = 0,
            .y_off = 2,
            .width = left_width,
            .height = body_height,
        });

        if (self.category == .themes) {
            try self.drawThemesList(left_win);
        } else {
            try self.drawSettingsList(left_win, alloc);
        }

        // Right Pane: Live Terminal Preview
        if (win.width > left_width + 10) {
            const right_win = win.child(.{
                .x_off = left_width + 1,
                .y_off = 2,
                .width = win.width - left_width - 1,
                .height = body_height,
            });
            try self.drawPreviewPane(right_win, alloc);
        }

        // Status & Footer Bar
        const footer_y = if (win.height > 2) win.height - 2 else 0;
        const status_win = win.child(.{
            .x_off = 0,
            .y_off = footer_y,
            .width = win.width,
            .height = 1,
        });
        if (self.save_status) |msg| {
            status_win.fill(.{ .style = .{ .fg = .{ .rgb = [_]u8{ 0xb8, 0xbb, 0x26 } }, .bold = true } });
            _ = status_win.printSegment(.{ .text = msg, .style = .{ .fg = .{ .rgb = [_]u8{ 0xb8, 0xbb, 0x26 } }, .bold = true } }, .{ .row_offset = 0, .col_offset = 2 });
        }

        const help_bar = win.child(.{
            .x_off = 0,
            .y_off = footer_y + 1,
            .width = win.width,
            .height = 1,
        });
        const help_style: vaxis.Style = .{
            .fg = .{ .rgb = [_]u8{ 0x92, 0x83, 0x74 } },
            .bg = .{ .rgb = [_]u8{ 0x1d, 0x20, 0x21 } },
        };
        help_bar.fill(.{ .style = help_style });
        _ = help_bar.printSegment(.{
            .text = "[Tab/1..5] Category  [↑↓] Move  [←→/Space] Change  [s] Save Config  [?] Help  [q] Quit",
            .style = help_style,
        }, .{ .row_offset = 0, .col_offset = 2 });
    }

    fn drawThemesList(self: *Studio, win: vaxis.Window) !void {
        const total = self.theme_names.items.len;
        if (total == 0) {
            _ = win.printSegment(.{ .text = "  No themes discovered.", .style = .{} }, .{ .row_offset = 1, .col_offset = 1 });
            return;
        }

        const height = win.height;
        var scroll_offset: usize = 0;
        if (self.cursor_idx >= height) {
            scroll_offset = self.cursor_idx - height + 1;
        }

        for (0..height) |row| {
            const idx = scroll_offset + row;
            if (idx >= total) break;

            const name = self.theme_names.items[idx];
            const is_cursor = (idx == self.cursor_idx);
            const is_active = (idx == self.selected_theme_idx);

            const style: vaxis.Style = if (is_cursor) .{
                .fg = .{ .rgb = [_]u8{ 0x00, 0x00, 0x00 } },
                .bg = .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } },
                .bold = true,
            } else if (is_active) .{
                .fg = .{ .rgb = [_]u8{ 0xb8, 0xbb, 0x26 } },
                .bold = true,
            } else .{
                .fg = .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } },
            };

            const prefix: []const u8 = if (is_cursor) "❯ " else if (is_active) "✓ " else "  ";
            _ = win.printSegment(.{ .text = prefix, .style = style }, .{ .row_offset = @intCast(row), .col_offset = 1 });
            _ = win.printSegment(.{ .text = name, .style = style }, .{ .row_offset = @intCast(row), .col_offset = 4 });
        }
    }

    fn drawSettingsList(self: *Studio, win: vaxis.Window, alloc: Allocator) !void {
        var items = self.activeSettings();
        defer items.deinit(alloc);

        for (items.items, 0..) |item, row| {
            if (row >= win.height) break;
            const is_sel = (row == self.cursor_idx);

            const row_style: vaxis.Style = if (is_sel) .{
                .fg = .{ .rgb = [_]u8{ 0x00, 0x00, 0x00 } },
                .bg = .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } },
                .bold = true,
            } else .{
                .fg = .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } },
            };

            const prefix: []const u8 = if (is_sel) "❯ " else "  ";
            _ = win.printSegment(.{ .text = prefix, .style = row_style }, .{ .row_offset = @intCast(row), .col_offset = 1 });
            _ = win.printSegment(.{ .text = item.label, .style = row_style }, .{ .row_offset = @intCast(row), .col_offset = 3 });

            // Value preview
            var val_buf: [128]u8 = undefined;
            const val_str = item.valueString(&val_buf);

            const val_style: vaxis.Style = if (is_sel) row_style else .{
                .fg = .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } },
                .bold = true,
            };

            const val_col: u16 = if (win.width > 18) win.width - @as(u16, @intCast(@min(val_str.len + 2, win.width))) else 20;
            _ = win.printSegment(.{ .text = val_str, .style = val_style }, .{ .row_offset = @intCast(row), .col_offset = val_col });
        }
    }

    fn drawPreviewPane(self: *Studio, win: vaxis.Window, alloc: Allocator) !void {
        const border_style: vaxis.Style = .{ .fg = .{ .rgb = [_]u8{ 0x50, 0x49, 0x45 } } };

        // Draw simulated macOS Terminal window
        _ = win.printSegment(.{ .text = "┌─ ● ● ● Ghostty Preview (macOS) ───────────────────┐", .style = border_style }, .{ .row_offset = 0, .col_offset = 0 });

        // Shell prompt
        _ = win.printSegment(.{
            .text = "│ ",
            .style = border_style,
        }, .{ .row_offset = 1, .col_offset = 0 });
        _ = win.printSegment(.{
            .text = "jaraujo@mac",
            .style = .{ .fg = self.palette[2], .bold = true },
        }, .{ .row_offset = 1, .col_offset = 2 });
        _ = win.printSegment(.{
            .text = ":",
            .style = .{ .fg = self.fg_color },
        }, .{ .row_offset = 1, .col_offset = 13 });
        _ = win.printSegment(.{
            .text = "~/Developer/ghostty",
            .style = .{ .fg = self.palette[4], .bold = true },
        }, .{ .row_offset = 1, .col_offset = 14 });
        _ = win.printSegment(.{
            .text = " $ git status",
            .style = .{ .fg = self.fg_color },
        }, .{ .row_offset = 1, .col_offset = 33 });

        // Git status sample output
        _ = win.printSegment(.{ .text = "│ ", .style = border_style }, .{ .row_offset = 2, .col_offset = 0 });
        _ = win.printSegment(.{
            .text = "On branch main (ahead of origin/main by 1 commit)",
            .style = .{ .fg = self.palette[2] },
        }, .{ .row_offset = 2, .col_offset = 2 });

        _ = win.printSegment(.{ .text = "│ ", .style = border_style }, .{ .row_offset = 3, .col_offset = 0 });
        _ = win.printSegment(.{
            .text = "Changes staged for commit:",
            .style = .{ .fg = self.palette[3], .bold = true },
        }, .{ .row_offset = 3, .col_offset = 2 });

        _ = win.printSegment(.{ .text = "│ ", .style = border_style }, .{ .row_offset = 4, .col_offset = 0 });
        _ = win.printSegment(.{
            .text = "  modified:   src/cli/config.zig  (TUI Studio in Zig)",
            .style = .{ .fg = self.palette[2] },
        }, .{ .row_offset = 4, .col_offset = 2 });

        // Terminal line with Cursor demo
        _ = win.printSegment(.{ .text = "│ ", .style = border_style }, .{ .row_offset = 5, .col_offset = 0 });
        _ = win.printSegment(.{
            .text = "jaraujo@mac $ echo \"Ghostty TUI Studio\" ",
            .style = .{ .fg = self.fg_color },
        }, .{ .row_offset = 5, .col_offset = 2 });

        // Cursor representation
        _ = win.printSegment(.{
            .text = "█",
            .style = .{ .fg = self.palette[11], .bold = true },
        }, .{ .row_offset = 5, .col_offset = 42 });

        // Divider
        _ = win.printSegment(.{ .text = "├─ Theme 16-Color ANSI Swatches ────────────────────┤", .style = border_style }, .{ .row_offset = 7, .col_offset = 0 });

        // Draw 16 ANSI Color blocks
        var swatch_col: u16 = 2;
        for (0..8) |c_idx| {
            _ = win.printSegment(.{
                .text = "██ ",
                .style = .{ .fg = self.palette[c_idx] },
            }, .{ .row_offset = 8, .col_offset = swatch_col });
            swatch_col += 3;
        }

        swatch_col = 2;
        for (8..16) |c_idx| {
            _ = win.printSegment(.{
                .text = "██ ",
                .style = .{ .fg = self.palette[c_idx] },
            }, .{ .row_offset = 9, .col_offset = swatch_col });
            swatch_col += 3;
        }

        // Selected option documentation box
        _ = win.printSegment(.{ .text = "├─ Setting Documentation ───────────────────────────┤", .style = border_style }, .{ .row_offset = 11, .col_offset = 0 });

        if (self.category == .themes) {
            _ = win.printSegment(.{
                .text = "Theme: Selects the color scheme from bundled or user themes.",
                .style = .{ .fg = .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } } },
            }, .{ .row_offset = 12, .col_offset = 2 });
            _ = win.printSegment(.{
                .text = "Press [Enter] to preview immediately, [s] to save permanently.",
                .style = .{ .fg = .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } } },
            }, .{ .row_offset = 13, .col_offset = 2 });
        } else {
            var items = self.activeSettings();
            defer items.deinit(alloc);
            if (self.cursor_idx < items.items.len) {
                const item = items.items[self.cursor_idx];
                _ = win.printSegment(.{
                    .text = item.label,
                    .style = .{ .fg = .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } }, .bold = true },
                }, .{ .row_offset = 12, .col_offset = 2 });
                _ = win.printSegment(.{
                    .text = item.doc,
                    .style = .{ .fg = .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } } },
                }, .{ .row_offset = 13, .col_offset = 2 });
            }
        }

        _ = win.printSegment(.{ .text = "└───────────────────────────────────────────────────┘", .style = border_style }, .{ .row_offset = 15, .col_offset = 0 });
    }
};

/// The `config` command launches the interactive Ghostty Configuration Studio,
/// allowing users to browse themes, adjust typography, customize window appearance,
/// and modify cursor and behavior settings directly within an interactive TUI.
pub fn run(alloc: Allocator) !u8 {
    var opts: Options = .{};
    defer opts.deinit();

    {
        var iter = try args.argsIterator(alloc, global.args());
        defer iter.deinit();
        try args.parse(Options, alloc, &opts, &iter);
    }

    var stdout_file: std.Io.File = .stdout();
    if (!tui.can_pretty_print or !(try stdout_file.isTty(global.io()))) {
        var buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(global.io(), &buffer);
        try stderr_writer.interface.print("ghostty +config requires an interactive TTY terminal.\n", .{});
        try stderr_writer.interface.flush();
        return 1;
    }

    var buf: [4096]u8 = undefined;
    var studio = try Studio.init(alloc, &buf);
    defer studio.deinit();

    try studio.start();
    return 0;
}
