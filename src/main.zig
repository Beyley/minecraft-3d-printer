const std = @import("std");
const ziggaratt = @import("ziggaratt");
const builtin = @import("builtin");

const Position = @Vector(3, isize);
const Vector3 = @Vector(3, f64);

pub const std_options = struct {
    pub const log_level = if (builtin.mode == .Debug) .debug else .info;
};

// directional mapping:
// gcode X+ == minecraft Z+
// gcode Y+ == minecraft X+
// gcode Z+ == minecraft Y+

const extrude = .west;
const updown_gantry = .south;
const forward_gantry = .east;
const reverse_direction = .north;
const step_side = .up;

pub fn main() !void {
    const bus = try ziggaratt.openBus();
    defer bus.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK");

    const allocator = gpa.allocator();

    const device = try bus.findDevice(allocator, .redstone);
    defer device.deinit();

    const redstone = try ziggaratt.Devices.Redstone.createFrom(device, allocator);

    //Reset all redstone to a default state
    try redstone.setRedstoneOutput(extrude, 0);
    try redstone.setRedstoneOutput(updown_gantry, 0);
    try redstone.setRedstoneOutput(forward_gantry, 0);
    try redstone.setRedstoneOutput(reverse_direction, 0);
    try redstone.setRedstoneOutput(step_side, 0);

    const input = std.mem.sliceTo(std.os.argv[1], 0);
    std.log.info("Loading file {s}...", .{input});

    const file = try std.fs.cwd().openFile(input, .{});
    defer file.close();

    const reader = file.reader();

    std.log.info("File {s} opened...", .{input});

    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |read| {
        const line = std.mem.trimRight(u8, read, "\r\n");

        // Skip comments
        if (line[0] == ';') continue;
        // Skip all M commands
        if (line[0] == 'M') continue;

        if (std.mem.startsWith(u8, line, "START_PRINT")) {
            std.log.err("TODO: handle START_PRINT macro", .{});
        }

        if (std.mem.startsWith(u8, line, "END_PRINT")) {
            std.log.err("TODO: handle END_PRINT macro", .{});
        }

        if (line[0] == 'G') {
            const command_str = std.mem.sliceTo(line[1..], ' ');

            const command = try std.fmt.parseInt(usize, command_str, 10);

            switch (command) {
                92 => {
                    //ignored
                },
                0 => {
                    try setExtrudeState(false, redstone);
                    try moveHead(try parsePosition(line), redstone);
                },
                1 => {
                    try setExtrudeState(true, redstone);
                    try moveHead(try parsePosition(line), redstone);
                },
                else => std.log.err("Unknown gcode {d}", .{command}),
            }
        }
    }

    //Reset all redstone to a default state
    try redstone.setRedstoneOutput(extrude, 0);
    try redstone.setRedstoneOutput(updown_gantry, 0);
    try redstone.setRedstoneOutput(forward_gantry, 0);
    try redstone.setRedstoneOutput(reverse_direction, 0);
    try redstone.setRedstoneOutput(step_side, 0);
}

/// Returns a parsed position, a missing field will contain the last known position
pub fn parsePosition(str: []const u8) !Position {
    var position = last_position;

    var iter = std.mem.splitScalar(u8, str, ' ');

    //Ignore the first word
    _ = iter.next();

    while (iter.next()) |component| {
        switch (component[0]) {
            'X' => position[0] = @intFromFloat(@trunc(try std.fmt.parseFloat(f32, component[1..]))),
            'Y' => position[1] = @intFromFloat(@trunc(try std.fmt.parseFloat(f32, component[1..]))),
            'Z' => position[2] = @intFromFloat(@trunc(try std.fmt.parseFloat(f32, component[1..]))),
            'E' => {
                //ignored
            },
            'F' => {
                //ignored
            },
            else => {
                std.log.err("Unknown position type {c} in component {s}\n", .{ component[0], component });
            },
        }
    }

    return position;
}

pub var last_extrude_state: bool = false;
pub var last_position: Position = .{ 0, 0, 0 };

pub fn setExtrudeState(state: bool, redstone: ziggaratt.Devices.Redstone) !void {
    defer last_extrude_state = state;
    if (state == last_extrude_state) return;

    std.log.info("Setting extrude state to {}", .{state});
    try redstone.setRedstoneOutput(extrude, if (state) 15 else 0);
}

///Move the head up in 10 game ticks
pub fn moveHeadUpDown(redstone: ziggaratt.Devices.Redstone, reversed: bool) !void {
    //3 ticks
    try redstone.setRedstoneOutput(updown_gantry, 0);
    try redstone.setRedstoneOutput(forward_gantry, 0);
    try redstone.setRedstoneOutput(reverse_direction, if (reversed) 15 else 0);
    //6 ticks
    for (0..7) |_| try redstone.setRedstoneOutput(step_side, 15);
    //1 tick
    try redstone.setRedstoneOutput(step_side, 0);
}

//Move the head forward in 10 game ticks
pub fn moveHeadForwardBackward(redstone: ziggaratt.Devices.Redstone, reversed: bool) !void {
    //3 ticks
    try redstone.setRedstoneOutput(updown_gantry, 15);
    try redstone.setRedstoneOutput(forward_gantry, 0);
    try redstone.setRedstoneOutput(reverse_direction, if (reversed) 15 else 0);
    //6 ticks
    for (0..7) |_| try redstone.setRedstoneOutput(step_side, 15);
    //1 tick
    try redstone.setRedstoneOutput(step_side, 0);
}

pub fn moveHeadRightLeft(redstone: ziggaratt.Devices.Redstone, reversed: bool) !void {
    //3 ticks
    try redstone.setRedstoneOutput(updown_gantry, 15);
    try redstone.setRedstoneOutput(forward_gantry, 15);
    try redstone.setRedstoneOutput(reverse_direction, if (reversed) 0 else 15);
    //6 ticks
    for (0..7) |_| try redstone.setRedstoneOutput(step_side, 15);
    //1 tick
    try redstone.setRedstoneOutput(step_side, 0);
}

var last_step_position: Position = .{ 0, 0, 0 };

pub fn moveHead(start_position: Position, redstone: ziggaratt.Devices.Redstone) !void {
    defer last_position = start_position;
    if (@reduce(.And, last_position == start_position)) return;
    std.log.info("Moving head to position {}", .{start_position});

    var p0 = last_position;
    const p1 = start_position;
    const d: Position = @intCast(@abs(p1 - p0));
    const step: Position = .{
        if (p0[0] < p1[0]) 1 else -1,
        if (p0[1] < p1[1]) 1 else -1,
        if (p0[2] < p1[2]) 1 else -1,
    };
    const hypotenuse = @sqrt(@reduce(.Add, Vector3{
        @floatFromInt(std.math.pow(isize, d[0], 2)),
        @floatFromInt(std.math.pow(isize, d[1], 2)),
        @floatFromInt(std.math.pow(isize, d[2], 2)),
    }));
    var tMax = @as(Vector3, @splat(hypotenuse * 0.5)) / @as(Vector3, @floatFromInt(d));
    const tDelta = @as(Vector3, @splat(hypotenuse)) / @as(Vector3, @floatFromInt(d));
    //While any of the values do not match their end positions
    while (@reduce(.Or, p0 != p1)) {
        if (tMax[0] < tMax[1]) {
            if (tMax[0] < tMax[2]) {
                p0[0] += step[0];
                tMax[0] += tDelta[0];
            } else if (tMax[0] > tMax[2]) {
                p0[2] += step[2];
                tMax[2] += tDelta[2];
            } else {
                p0[0] += step[0];
                tMax[0] += tDelta[0];
                p0[2] += step[2];
                tMax[2] += tDelta[2];
            }
        } else if (tMax[0] > tMax[1]) {
            if (tMax[1] < tMax[2]) {
                p0[1] += step[1];
                tMax[1] += tDelta[1];
            } else if (tMax[1] > tMax[2]) {
                p0[2] += step[2];
                tMax[2] += tDelta[2];
            } else {
                p0[1] += step[1];
                tMax[1] += tDelta[1];
                p0[2] += step[2];
                tMax[2] += tDelta[2];
            }
        } else {
            if (tMax[1] < tMax[2]) {
                p0[1] += step[1];
                tMax[1] += tDelta[1];
                p0[0] += step[0];
                tMax[0] += tDelta[0];
            } else if (tMax[1] > tMax[2]) {
                p0[2] += step[2];
                tMax[2] += tDelta[2];
            } else {
                p0 += step;
                tMax += tDelta;
            }
        }

        std.log.info("plot {}", .{p0});

        while (last_step_position[0] < p0[0]) {
            try moveHeadRightLeft(redstone, false);
            last_step_position[0] += 1;
        }
        while (last_step_position[0] > p0[0]) {
            try moveHeadRightLeft(redstone, true);
            last_step_position[0] -= 1;
        }
        while (last_step_position[1] < p0[1]) {
            try moveHeadForwardBackward(redstone, false);
            last_step_position[1] += 1;
        }
        while (last_step_position[1] > p0[1]) {
            try moveHeadForwardBackward(redstone, true);
            last_step_position[1] -= 1;
        }
        while (last_step_position[2] < p0[2]) {
            try moveHeadUpDown(redstone, false);
            last_step_position[2] += 1;
        }
        while (last_step_position[2] > p0[2]) {
            try moveHeadUpDown(redstone, true);
            last_step_position[2] -= 1;
        }
    }
}
