const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ziggaratt = b.dependency("ziggaratt", .{}).module("ziggaratt");

    const exe = b.addExecutable(.{
        .name = "minecraft-printer",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    if (target.cpu_arch == .riscv64) {
        var feature_set = std.Target.Cpu.Feature.Set.empty;
        feature_set.addFeature(@intFromEnum(std.Target.riscv.Feature.d));
        feature_set.addFeature(@intFromEnum(std.Target.riscv.Feature.f));
        exe.target.cpu_features_sub = feature_set;
    }
    exe.linkLibC();
    exe.addModule("ziggaratt", ziggaratt);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
