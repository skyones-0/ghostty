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
            .window => "🪟 Window & Styling",
            .cursor => "🖱️ Cursor & Mouse",
            .behavior => "⚡ Behavior & Terminal",
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

const ThemeEntry = struct {
    name: []const u8,
    path: []const u8,

    fn lessThan(_: void, lhs: ThemeEntry, rhs: ThemeEntry) bool {
        return std.ascii.orderIgnoreCase(lhs.name, rhs.name) == .lt;
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

    // Default string value according to Ghostty defaults
    default_str: []const u8,
    // Value loaded from user's file (null if absent)
    initial_file_val: ?[]const u8 = null,

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
                return std.fmt.bufPrint(buf, "{d:.2}", .{self.float_val}) catch "0.00";
            },
            .number_int => {
                return std.fmt.bufPrint(buf, "{d}", .{self.int_val}) catch "0";
            },
        }
    }

    pub fn isChangedFromDefault(self: *const SettingItem) bool {
        var buf: [128]u8 = undefined;
        const current = self.valueString(&buf);
        return !std.ascii.eqlIgnoreCase(current, self.default_str);
    }

    pub fn resetToDefault(self: *SettingItem) void {
        switch (self.setting_type) {
            .choice => {
                for (self.choices, 0..) |ch, idx| {
                    if (std.ascii.eqlIgnoreCase(ch, self.default_str)) {
                        self.choice_idx = idx;
                        break;
                    }
                }
            },
            .boolean => {
                self.bool_val = std.mem.eql(u8, self.default_str, "true");
            },
            .number_float => {
                if (std.fmt.parseFloat(f64, self.default_str)) |fv| {
                    self.float_val = fv;
                } else |_| {}
            },
            .number_int => {
                if (std.fmt.parseInt(i64, self.default_str, 10)) |iv| {
                    self.int_val = iv;
                } else |_| {}
            },
        }
        self.modified = true;
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

    // Discovered themes list
    themes: std.ArrayList(ThemeEntry),
    selected_theme_idx: usize = 0,
    initial_theme_in_file: ?[]const u8 = null,

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
            .themes = .empty,
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
        for (self.settings.items) |item| {
            if (item.initial_file_val) |v| allocator.free(v);
        }
        self.settings.deinit(allocator);

        for (self.themes.items) |t| {
            allocator.free(t.name);
            allocator.free(t.path);
        }
        self.themes.deinit(allocator);

        if (self.initial_theme_in_file) |t| allocator.free(t);

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

                var already = false;
                for (self.themes.items) |existing| {
                    if (std.mem.eql(u8, existing.name, entry.name)) {
                        already = true;
                        break;
                    }
                }
                if (already) continue;

                const path = try std.fs.path.join(self.allocator, &.{ loc.dir, entry.name });
                try self.themes.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .path = path,
                });
            }
        }

        std.mem.sortUnstable(ThemeEntry, self.themes.items, {}, ThemeEntry.lessThan);
    }

    fn initSettings(self: *Studio) !void {
        const alloc = self.allocator;

        // ==========================================
        // Category 1: Typography & Fonts
        // ==========================================
        try self.settings.append(alloc, .{
            .key = "font-family",
            .label = "Font Family",
            .doc = "Primary font family for terminal rendering. Requires full restart or redraw.",
            .category = .typography,
            .setting_type = .choice,
            .default_str = "MesloLGS NF",
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
                "Source Code Pro",
                "DejaVu Sans Mono",
                "Ubuntu Mono",
            },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "font-size",
            .label = "Font Size (pt)",
            .doc = "Main terminal font size in points.",
            .category = .typography,
            .setting_type = .number_float,
            .default_str = "14.00",
            .float_val = 14.0,
            .float_min = 8.0,
            .float_max = 36.0,
            .float_step = 0.5,
        });

        try self.settings.append(alloc, .{
            .key = "font-thicken",
            .label = "Font Thicken (Retina)",
            .doc = "Thickens glyph strokes slightly for enhanced readability on high-DPI screens.",
            .category = .typography,
            .setting_type = .boolean,
            .default_str = "false",
            .bool_val = false,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-cell-width",
            .label = "Adjust Cell Width (%)",
            .doc = "Horizontal character cell spacing adjustment relative to font width.",
            .category = .typography,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = -20,
            .int_max = 50,
            .int_step = 1,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-cell-height",
            .label = "Adjust Cell Height (%)",
            .doc = "Vertical line spacing adjustment relative to font line height.",
            .category = .typography,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = -20,
            .int_max = 50,
            .int_step = 1,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-font-baseline",
            .label = "Font Baseline Offset (%)",
            .doc = "Vertical position shift for font rendering baseline.",
            .category = .typography,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = -20,
            .int_max = 20,
            .int_step = 1,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-underline-position",
            .label = "Underline Position",
            .doc = "Offset in pixels for underline and strike-through decoration.",
            .category = .typography,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = -10,
            .int_max = 10,
            .int_step = 1,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-underline-thickness",
            .label = "Underline Thickness (%)",
            .doc = "Stroke thickness of underlines as a percentage of standard stroke.",
            .category = .typography,
            .setting_type = .number_int,
            .default_str = "100",
            .int_val = 100,
            .int_min = 20,
            .int_max = 300,
            .int_step = 10,
        });

        // ==========================================
        // Category 2: Window & Styling (including fork features)
        // ==========================================
        try self.settings.append(alloc, .{
            .key = "background-opacity",
            .label = "Background Opacity",
            .doc = "Window transparency from 0.10 (translucent) to 1.00 (fully opaque).",
            .category = .window,
            .setting_type = .number_float,
            .default_str = "1.00",
            .float_val = 1.0,
            .float_min = 0.10,
            .float_max = 1.0,
            .float_step = 0.05,
        });

        try self.settings.append(alloc, .{
            .key = "background-blur",
            .label = "Background Blur Radius",
            .doc = "Gaussian blur radius behind transparent background on macOS.",
            .category = .window,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = 0,
            .int_max = 100,
            .int_step = 5,
        });

        try self.settings.append(alloc, .{
            .key = "macos-topbar",
            .label = "macOS Top Bar (Fork)",
            .doc = "Enables the modern macOS top bar with path, split controls, and sidebar toggle.",
            .category = .window,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "macos-topbar-palette",
            .label = "Topbar Palette Button (Fork)",
            .doc = "Shows the Command Palette shortcut button in the macOS top bar.",
            .category = .window,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "macos-titlebar-style",
            .label = "macOS Titlebar Style",
            .doc = "Visual style of the window titlebar chrome.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "transparent",
            .choices = &.{ "transparent", "native", "tabs", "hidden" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "macos-titlebar-proxy-icon",
            .label = "Titlebar Proxy Icon",
            .doc = "Visibility of the document proxy icon in the macOS window titlebar.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "visible",
            .choices = &.{ "visible", "hidden" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "macos-window-buttons",
            .label = "Traffic Light Buttons",
            .doc = "Visibility of macOS close, minimize, and zoom buttons.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "visible",
            .choices = &.{ "visible", "hidden" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "macos-window-shadow",
            .label = "macOS Window Shadow",
            .doc = "Draws the standard macOS drop shadow around terminal windows.",
            .category = .window,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "macos-icon",
            .label = "Dock App Icon",
            .doc = "Custom icon variant rendered in macOS Dock and App Switcher.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "official",
            .choices = &.{ "official", "glass", "retro", "chalk", "paper", "blueprint", "hologram" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "macos-non-native-fullscreen",
            .label = "Fullscreen Behavior",
            .doc = "Non-native macOS fullscreen (fast, overlay, or visible-menu).",
            .category = .window,
            .setting_type = .choice,
            .default_str = "false",
            .choices = &.{ "false", "true", "visible-menu" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "macos-dock-drop-behavior",
            .label = "Dock Icon Drop Action",
            .doc = "Action taken when files or directories are dragged to Ghostty dock icon.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "new-tab",
            .choices = &.{ "new-tab", "new-window" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "window-padding-x",
            .label = "Window Padding X (px)",
            .doc = "Horizontal margin padding between terminal text grid and window border.",
            .category = .window,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = 0,
            .int_max = 64,
            .int_step = 2,
        });

        try self.settings.append(alloc, .{
            .key = "window-padding-y",
            .label = "Window Padding Y (px)",
            .doc = "Vertical margin padding between terminal text grid and window border.",
            .category = .window,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = 0,
            .int_max = 64,
            .int_step = 2,
        });

        try self.settings.append(alloc, .{
            .key = "window-padding-balance",
            .label = "Balance Window Padding",
            .doc = "Evenly balances remaining grid margin space across all sides.",
            .category = .window,
            .setting_type = .boolean,
            .default_str = "false",
            .bool_val = false,
        });

        try self.settings.append(alloc, .{
            .key = "window-padding-color",
            .label = "Padding Color",
            .doc = "Color filled in the padding margins (background or extended text background).",
            .category = .window,
            .setting_type = .choice,
            .default_str = "background",
            .choices = &.{ "background", "extend" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "window-save-state",
            .label = "Window State Restoration",
            .doc = "Persist and restore open windows, tabs, and positions on launch.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "default",
            .choices = &.{ "default", "always", "never" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "window-colorspace",
            .label = "Color Space",
            .doc = "Output color space (standard sRGB or Apple wide-gamut Display P3).",
            .category = .window,
            .setting_type = .choice,
            .default_str = "srgb",
            .choices = &.{ "srgb", "display-p3" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "window-theme",
            .label = "Window Chrome Theme",
            .doc = "Operating system appearance theme for window decorations.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "auto",
            .choices = &.{ "auto", "system", "dark", "light" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "split-divider-color",
            .label = "Split Divider Color",
            .doc = "Hex color string for split pane border lines.",
            .category = .window,
            .setting_type = .choice,
            .default_str = "auto",
            .choices = &.{ "auto", "#FFEAA7", "#3C3836", "#504945", "#282828", "#FABD2F" },
            .choice_idx = 0,
        });

        // ==========================================
        // Category 3: Cursor & Mouse
        // ==========================================
        try self.settings.append(alloc, .{
            .key = "cursor-style",
            .label = "Cursor Style",
            .doc = "Visual shape of the terminal text cursor.",
            .category = .cursor,
            .setting_type = .choice,
            .default_str = "block",
            .choices = &.{ "block", "bar", "underline" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "cursor-style-blink",
            .label = "Cursor Blinking",
            .doc = "Controls cursor blink animation behavior.",
            .category = .cursor,
            .setting_type = .choice,
            .default_str = "false",
            .choices = &.{ "false", "true", "system" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "cursor-color",
            .label = "Cursor Color",
            .doc = "Custom color for the cursor instead of inverting foreground/background.",
            .category = .cursor,
            .setting_type = .choice,
            .default_str = "auto",
            .choices = &.{ "auto", "#FABD2F", "#B8BB26", "#83A598", "#FB4934", "#EBDBB2", "#FFFFFF" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "cursor-opacity",
            .label = "Cursor Opacity",
            .doc = "Transparency level of the cursor from 0.10 to 1.00.",
            .category = .cursor,
            .setting_type = .number_float,
            .default_str = "1.00",
            .float_val = 1.0,
            .float_min = 0.10,
            .float_max = 1.0,
            .float_step = 0.05,
        });

        try self.settings.append(alloc, .{
            .key = "adjust-cursor-thickness",
            .label = "Cursor Thickness (%)",
            .doc = "Stroke thickness for bar and underline cursor shapes.",
            .category = .cursor,
            .setting_type = .number_int,
            .default_str = "0",
            .int_val = 0,
            .int_min = 0,
            .int_max = 100,
            .int_step = 5,
        });

        try self.settings.append(alloc, .{
            .key = "mouse-hide-while-typing",
            .label = "Hide Mouse While Typing",
            .doc = "Automatically hides mouse cursor when keyboard keys are pressed.",
            .category = .cursor,
            .setting_type = .boolean,
            .default_str = "false",
            .bool_val = false,
        });

        try self.settings.append(alloc, .{
            .key = "mouse-shift-capture",
            .label = "Shift Mouse Bypass",
            .doc = "Holding Shift bypasses terminal mouse reporting for native text selection.",
            .category = .cursor,
            .setting_type = .choice,
            .default_str = "true",
            .choices = &.{ "true", "false", "never", "always" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "mouse-scroll-multiplier",
            .label = "Mouse Scroll Speed",
            .doc = "Multiplier scaling the scroll speed of mouse wheels and trackpads.",
            .category = .cursor,
            .setting_type = .number_float,
            .default_str = "1.00",
            .float_val = 1.0,
            .float_min = 0.25,
            .float_max = 5.0,
            .float_step = 0.25,
        });

        try self.settings.append(alloc, .{
            .key = "right-click-action",
            .label = "Right-Click Action",
            .doc = "Action performed on right-clicking: open context menu or paste clipboard.",
            .category = .cursor,
            .setting_type = .choice,
            .default_str = "context-menu",
            .choices = &.{ "context-menu", "paste" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "copy-on-select",
            .label = "Copy on Select",
            .doc = "Automatically copies highlighted text to system or primary clipboard.",
            .category = .cursor,
            .setting_type = .choice,
            .default_str = "false",
            .choices = &.{ "false", "clipboard", "primary" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "selection-clear-on-typing",
            .label = "Clear Selection on Typing",
            .doc = "Clears active text selection when any key is pressed.",
            .category = .cursor,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "selection-clear-on-copy",
            .label = "Clear Selection on Copy",
            .doc = "Clears active text selection immediately after copying.",
            .category = .cursor,
            .setting_type = .boolean,
            .default_str = "false",
            .bool_val = false,
        });

        // ==========================================
        // Category 4: Behavior, Terminal & Quick Features
        // ==========================================
        try self.settings.append(alloc, .{
            .key = "quick-terminal-position",
            .label = "Quick Terminal Position",
            .doc = "Screen edge where the Quake-style dropdown terminal appears.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "top",
            .choices = &.{ "top", "bottom", "left", "right" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "quick-terminal-size",
            .label = "Quick Terminal Size",
            .doc = "Screen coverage percentage of the dropdown quick terminal.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "30%",
            .choices = &.{ "20%", "30%", "40%", "50%", "60%", "80%" },
            .choice_idx = 1,
        });

        try self.settings.append(alloc, .{
            .key = "quick-terminal-autohide",
            .label = "Quick Terminal Auto-Hide",
            .doc = "Automatically closes the dropdown terminal when focus is lost.",
            .category = .behavior,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "quick-terminal-animation-duration",
            .label = "Quick Terminal Slide (s)",
            .doc = "Slide animation duration in seconds for quick terminal appearance.",
            .category = .behavior,
            .setting_type = .number_float,
            .default_str = "0.20",
            .float_val = 0.20,
            .float_min = 0.0,
            .float_max = 0.6,
            .float_step = 0.05,
        });

        try self.settings.append(alloc, .{
            .key = "scrollback-limit",
            .label = "Scrollback Buffer (Bytes)",
            .doc = "Maximum memory limit in bytes allocated for terminal history lines.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "10485760",
            .choices = &.{ "1073741824", "104857600", "10485760", "1048576", "524288" },
            .choice_idx = 2,
        });

        try self.settings.append(alloc, .{
            .key = "scroll-to-bottom",
            .label = "Scroll to Bottom Mode",
            .doc = "When to automatically snap scroll view back to bottom prompt.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "all",
            .choices = &.{ "all", "keystroke, no-output", "no-output", "keystroke", "none" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "bell-features",
            .label = "Bell Features",
            .doc = "Terminal audio/visual alert behavior on terminal BEL character.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "system",
            .choices = &.{ "system", "audio", "visual", "attention", "none" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "bell-audio-volume",
            .label = "Bell Audio Volume",
            .doc = "Volume level for custom terminal bell sound (0.0 to 1.0).",
            .category = .behavior,
            .setting_type = .number_float,
            .default_str = "1.00",
            .float_val = 1.0,
            .float_min = 0.0,
            .float_max = 1.0,
            .float_step = 0.1,
        });

        try self.settings.append(alloc, .{
            .key = "confirm-close-surface",
            .label = "Confirm Close Surface",
            .doc = "Displays confirmation alert before closing terminal tab or split.",
            .category = .behavior,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "quit-after-last-window-closed",
            .label = "Quit on Window Close",
            .doc = "Quits the entire macOS Ghostty application when the last window closes.",
            .category = .behavior,
            .setting_type = .boolean,
            .default_str = "false",
            .bool_val = false,
        });

        try self.settings.append(alloc, .{
            .key = "notify-on-command-finish",
            .label = "Command Finish Alerts",
            .doc = "Send desktop notification when long-running shell commands complete.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "never",
            .choices = &.{ "never", "always", "unfocused" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "notify-on-command-finish-action",
            .label = "Command Alert Action",
            .doc = "Notification style for completed background commands.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "bell",
            .choices = &.{ "bell", "notify" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "clipboard-read",
            .label = "Clipboard Read Policy",
            .doc = "Security prompt policy when terminal programs request reading clipboard.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "ask",
            .choices = &.{ "ask", "allow", "deny" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "clipboard-write",
            .label = "Clipboard Write Policy",
            .doc = "Security prompt policy when terminal programs write to system clipboard.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "allow",
            .choices = &.{ "allow", "ask", "deny" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "clipboard-trim-trailing-spaces",
            .label = "Trim Trailing Spaces",
            .doc = "Strips useless trailing whitespace characters when copying text.",
            .category = .behavior,
            .setting_type = .boolean,
            .default_str = "false",
            .bool_val = false,
        });

        try self.settings.append(alloc, .{
            .key = "clipboard-paste-protection",
            .label = "Paste Protection Alert",
            .doc = "Warns before pasting commands with newlines to prevent accidental execution.",
            .category = .behavior,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "clipboard-paste-bracketed-safe",
            .label = "Bracketed Paste Safety",
            .doc = "Prevents bracketed paste bypasses by escaping special terminal sequences.",
            .category = .behavior,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
        });

        try self.settings.append(alloc, .{
            .key = "working-directory",
            .label = "New Tab Working Directory",
            .doc = "Initial working directory for new windows, tabs, and splits.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "home",
            .choices = &.{ "home", "current", "previous" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "auto-update",
            .label = "Auto Update Mode",
            .doc = "Automatic background update check and download mode on macOS.",
            .category = .behavior,
            .setting_type = .choice,
            .default_str = "off",
            .choices = &.{ "off", "check", "download" },
            .choice_idx = 0,
        });

        try self.settings.append(alloc, .{
            .key = "custom-shader-animation",
            .label = "Custom Shader Animation",
            .doc = "Continuously animate GLSL custom shader effects (e.g. bloom, crt).",
            .category = .behavior,
            .setting_type = .boolean,
            .default_str = "true",
            .bool_val = true,
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
                    if (self.initial_theme_in_file) |t| self.allocator.free(t);
                    self.initial_theme_in_file = self.allocator.dupe(u8, val) catch null;

                    for (self.themes.items, 0..) |t, idx| {
                        if (std.ascii.eqlIgnoreCase(t.name, val)) {
                            self.selected_theme_idx = idx;
                            self.cursor_idx = idx;
                            break;
                        }
                    }
                }

                for (self.settings.items) |*item| {
                    if (std.mem.eql(u8, item.key, key)) {
                        if (item.initial_file_val) |v| self.allocator.free(v);
                        item.initial_file_val = self.allocator.dupe(u8, val) catch null;

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

    fn findSetting(self: *Studio, key: []const u8) ?*SettingItem {
        for (self.settings.items) |*item| {
            if (std.mem.eql(u8, item.key, key)) return item;
        }
        return null;
    }

    fn getActiveSetting(self: *Studio, index: usize) ?*SettingItem {
        var current: usize = 0;
        for (self.settings.items) |*item| {
            if (item.category == self.category) {
                if (current == index) return item;
                current += 1;
            }
        }
        return null;
    }

    fn getActiveSettingConst(self: *const Studio, index: usize) ?*const SettingItem {
        var current: usize = 0;
        for (self.settings.items) |*item| {
            if (item.category == self.category) {
                if (current == index) return item;
                current += 1;
            }
        }
        return null;
    }

    fn activeItemCount(self: *Studio) usize {
        if (self.category == .themes) {
            return self.themes.items.len;
        }
        var count: usize = 0;
        for (self.settings.items) |item| {
            if (item.category == self.category) count += 1;
        }
        return count;
    }

    fn updateThemeColorsFor(self: *Studio, theme_idx: usize) void {
        if (self.themes.items.len == 0 or theme_idx >= self.themes.items.len) return;

        const path = self.themes.items[theme_idx].path;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var cfg = Config.default(arena.allocator()) catch return;
        cfg.loadFile(arena.allocator(), path) catch return;

        inline for (0..16) |i| {
            const rgb = cfg.palette.value[i];
            self.palette[i] = .{ .rgb = [_]u8{ rgb.r, rgb.g, rgb.b } };
        }
        self.fg_color = .{
            .rgb = [_]u8{ cfg.foreground.r, cfg.foreground.g, cfg.foreground.b },
        };
        self.bg_color = .{
            .rgb = [_]u8{ cfg.background.r, cfg.background.g, cfg.background.b },
        };
    }

    fn updateThemeColors(self: *Studio) void {
        self.updateThemeColorsFor(self.selected_theme_idx);
    }

    pub fn start(self: *Studio) !void {
        var loop: vaxis.Loop(Event) = .init(global.io(), &self.tty, &self.vx);
        try loop.start();
        defer loop.stop();

        const writer = self.tty.writer();
        try self.vx.enterAltScreen(writer);
        try self.vx.setTitle(writer, "👻 Ghostty Configuration Studio");
        try self.vx.queryTerminal(writer, .fromSeconds(1));
        try self.vx.setMouseMode(writer, true);

        while (!self.should_quit) {
            try loop.pollEvent();
            while (try loop.tryEvent()) |event| {
                try self.update(event);
            }
            try self.draw();

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
                if (key.matches('1', .{})) {
                    self.category = .themes;
                    self.cursor_idx = self.selected_theme_idx;
                    return;
                }
                if (key.matches('2', .{})) { self.category = .typography; self.cursor_idx = 0; return; }
                if (key.matches('3', .{})) { self.category = .window; self.cursor_idx = 0; return; }
                if (key.matches('4', .{})) { self.category = .cursor; self.cursor_idx = 0; return; }
                if (key.matches('5', .{})) { self.category = .behavior; self.cursor_idx = 0; return; }

                if (key.matches(vaxis.Key.tab, .{})) {
                    const next_cat = (@intFromEnum(self.category) + 1) % 5;
                    self.category = @enumFromInt(next_cat);
                    self.cursor_idx = if (self.category == .themes) self.selected_theme_idx else 0;
                    return;
                }

                if (key.matches(vaxis.Key.tab, .{ .shift = true })) {
                    const prev_cat = if (@intFromEnum(self.category) == 0) 4 else @intFromEnum(self.category) - 1;
                    self.category = @enumFromInt(prev_cat);
                    self.cursor_idx = if (self.category == .themes) self.selected_theme_idx else 0;
                    return;
                }

                // Reset to default
                if (key.matches('d', .{})) {
                    if (self.category != .themes) {
                        if (self.getActiveSetting(self.cursor_idx)) |item| {
                            item.resetToDefault();
                            self.save_status = "Reset to default. Press [s] to save.";
                        }
                    }
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
                            self.updateThemeColorsFor(self.cursor_idx);
                        }
                    }
                    return;
                }

                if (key.matchesAny(&.{ vaxis.Key.down, 'j' }, .{})) {
                    if (count > 0) {
                        self.cursor_idx = (self.cursor_idx + 1) % count;
                        if (self.category == .themes) {
                            self.updateThemeColorsFor(self.cursor_idx);
                        }
                    }
                    return;
                }

                // Edit values with Left / Right / Space / Enter
                if (self.category == .themes) {
                    if (key.matchesAny(&.{ vaxis.Key.enter, ' ' }, .{})) {
                        self.selected_theme_idx = self.cursor_idx;
                        self.updateThemeColors();
                        self.save_status = "✓ Theme applied! Press [s] to save to ~/.config/ghostty/config.";
                    }
                } else {
                    if (self.getActiveSetting(self.cursor_idx)) |item| {
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

        // Open file for atomic write
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

                    if (std.mem.eql(u8, key, "theme") and self.themes.items.len > 0) {
                        const theme_name = self.themes.items[self.selected_theme_idx].name;
                        try w.interface.print("theme = \"{s}\"\n", .{theme_name});
                        try updated_keys.put("theme", {});
                        handled = true;
                    } else if (self.findSetting(key)) |item| {
                        var val_buf: [128]u8 = undefined;
                        const val_str = item.valueString(&val_buf);

                        if (std.mem.eql(u8, val_str, item.default_str)) {
                            // User returned value back to default: comment it out
                            try w.interface.print("# {s} = {s}\n", .{ key, val_str });
                        } else {
                            if (item.setting_type == .choice) {
                                try w.interface.print("{s} = \"{s}\"\n", .{ key, val_str });
                            } else {
                                try w.interface.print("{s} = {s}\n", .{ key, val_str });
                            }
                        }
                        try updated_keys.put(item.key, {});
                        handled = true;
                    }
                }
            }

            if (!handled) {
                try w.interface.print("{s}\n", .{raw_line});
            }
        }

        // For settings NOT present in user's file:
        // ONLY append them if they differ from Ghostty default!
        for (self.settings.items) |item| {
            if (!updated_keys.contains(item.key)) {
                if (item.isChangedFromDefault()) {
                    var val_buf: [128]u8 = undefined;
                    const val_str = item.valueString(&val_buf);
                    if (item.setting_type == .choice) {
                        try w.interface.print("{s} = \"{s}\"\n", .{ item.key, val_str });
                    } else {
                        try w.interface.print("{s} = {s}\n", .{ item.key, val_str });
                    }
                }
            }
        }

        // Theme addition if not present in file
        if (!updated_keys.contains("theme") and self.themes.items.len > 0) {
            const theme_name = self.themes.items[self.selected_theme_idx].name;
            try w.interface.print("\ntheme = \"{s}\"\n", .{theme_name});
        }

        try w.interface.flush();
        self.save_status = "✓ Saved to ~/.config/ghostty/config! Ghostty reloaded.";
    }

    pub fn draw(self: *Studio) !void {
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
            .text = " 👻 GHOSTTY CONFIG STUDIO — Interactive Native TUI",
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
        const left_width = if (win.width > 70) @min(42, win.width / 2) else win.width;

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
            try self.drawSettingsList(left_win);
        }

        // Right Pane: Live Terminal Preview
        if (win.width > left_width + 10) {
            const right_win = win.child(.{
                .x_off = left_width + 1,
                .y_off = 2,
                .width = win.width - left_width - 1,
                .height = body_height,
            });
            try self.drawPreviewPane(right_win);
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
            .text = "[Tab/1..5] Category  [↑↓] Move  [←→] Change  [d] Default  [s] Save Config  [q] Quit",
            .style = help_style,
        }, .{ .row_offset = 0, .col_offset = 2 });
    }

    fn drawThemesList(self: *Studio, win: vaxis.Window) !void {
        const total = self.themes.items.len;
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

            const name = self.themes.items[idx].name;
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

    fn drawSettingsList(self: *Studio, win: vaxis.Window) !void {
        const height = win.height;
        var scroll_offset: usize = 0;
        if (self.cursor_idx >= height) {
            scroll_offset = self.cursor_idx - height + 1;
        }

        var cat_idx: usize = 0;
        var row: u16 = 0;
        for (self.settings.items) |*item| {
            if (item.category != self.category) continue;
            defer cat_idx += 1;

            if (cat_idx < scroll_offset) continue;
            if (row >= height) break;
            defer row += 1;

            const is_sel = (cat_idx == self.cursor_idx);

            const row_style: vaxis.Style = if (is_sel) .{
                .fg = .{ .rgb = [_]u8{ 0x00, 0x00, 0x00 } },
                .bg = .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } },
                .bold = true,
            } else .{
                .fg = .{ .rgb = [_]u8{ 0xeb, 0xdb, 0xb2 } },
            };

            const prefix: []const u8 = if (is_sel) "❯ " else "  ";
            _ = win.printSegment(.{ .text = prefix, .style = row_style }, .{ .row_offset = row, .col_offset = 1 });
            _ = win.printSegment(.{ .text = item.label, .style = row_style }, .{ .row_offset = row, .col_offset = 3 });

            // Value preview
            var val_buf: [128]u8 = undefined;
            const val_str = item.valueString(&val_buf);

            const is_changed = item.isChangedFromDefault();
            const val_style: vaxis.Style = if (is_sel) row_style else if (is_changed) .{
                .fg = .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } },
                .bold = true,
            } else .{
                .fg = .{ .rgb = [_]u8{ 0x92, 0x83, 0x74 } },
            };

            const val_col: u16 = if (win.width > val_str.len + 4)
                win.width -| @as(u16, @intCast(val_str.len + 2))
            else
                win.width -| @as(u16, @intCast(val_str.len));
            _ = win.printSegment(.{ .text = val_str, .style = val_style }, .{ .row_offset = row, .col_offset = val_col });
        }
    }

    fn drawPreviewPane(self: *Studio, win: vaxis.Window) !void {
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
            .text = "jaraujo@mac $ echo \"Ghostty Studio\" ",
            .style = .{ .fg = self.fg_color },
        }, .{ .row_offset = 5, .col_offset = 2 });

        // Cursor representation based on setting
        var cursor_char: []const u8 = "█";
        if (self.findSetting("cursor-style")) |cs| {
            var buf: [128]u8 = undefined;
            const style_str = cs.valueString(&buf);
            if (std.mem.eql(u8, style_str, "bar")) {
                cursor_char = "│";
            } else if (std.mem.eql(u8, style_str, "underline")) {
                cursor_char = "_";
            }
        }
        _ = win.printSegment(.{
            .text = cursor_char,
            .style = .{ .fg = self.palette[11], .bold = true },
        }, .{ .row_offset = 5, .col_offset = 38 });

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
            const active_name = if (self.themes.items.len > 0 and self.selected_theme_idx < self.themes.items.len)
                self.themes.items[self.selected_theme_idx].name
            else
                "Default";
            var tbuf: [128]u8 = undefined;
            const tmsg = std.fmt.bufPrint(&tbuf, "Active Theme: {s} (Total themes: {d})", .{ active_name, self.themes.items.len }) catch "Themes";
            _ = win.printSegment(.{
                .text = tmsg,
                .style = .{ .fg = .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } }, .bold = true },
            }, .{ .row_offset = 12, .col_offset = 2 });
            _ = win.printSegment(.{
                .text = "[↑↓] Browse themes (live preview)  [Enter] Apply  [s] Save permanently",
                .style = .{ .fg = .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } } },
            }, .{ .row_offset = 13, .col_offset = 2 });
        } else {
            if (self.getActiveSettingConst(self.cursor_idx)) |item| {
                var val_buf: [128]u8 = undefined;
                const val_str = item.valueString(&val_buf);
                const is_changed = item.isChangedFromDefault();

                var lbuf: [128]u8 = undefined;
                const status_tag = if (is_changed) " (Modified - will be written)" else " (Default - not written)";
                const title_line = std.fmt.bufPrint(&lbuf, "{s}: {s}{s}", .{ item.label, val_str, status_tag }) catch item.label;

                _ = win.printSegment(.{
                    .text = title_line,
                    .style = .{ .fg = if (is_changed) .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } } else .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } }, .bold = true },
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
    if (!(stdout_file.isTty(global.io()) catch false)) {
        var buffer: [1024]u8 = undefined;
        var stdout_writer = stdout_file.writer(global.io(), &buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("ghostty +config requires an interactive terminal TTY.\n", .{});
        try stdout.flush();
        return 1;
    }

    var tty_buf: [4096]u8 = undefined;
    const studio = try Studio.init(alloc, &tty_buf);
    defer studio.deinit();

    try studio.start();
    return 0;
}
