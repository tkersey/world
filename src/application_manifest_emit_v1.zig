const std = @import("std");
const application = @import("world_application");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const binary_path = args.next() orelse return error.InvalidArguments;
    const projection_path = args.next() orelse return error.InvalidArguments;
    if (args.next() != null) return error.InvalidArguments;

    const manifest = application.App.Manifest;
    const binary = try manifest.encode(allocator);
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = binary_path,
        .data = binary,
    });

    const application_id = std.fmt.bytesToHex(manifest.application_id, .lower);
    const root_program_id = std.fmt.bytesToHex(manifest.root_program_id, .lower);
    var projection: std.ArrayList(u8) = .empty;
    defer projection.deinit(allocator);
    try projection.print(
        allocator,
        \\application_name={s}
        \\application_version={s}
        \\application_id={s}
        \\world_application_abi_version={d}
        \\world_package_version={s}
        \\boundary_static_machine_abi_version={d}
        \\boundary_package_version={s}
        \\root_program_id={s}
        \\internal_handler_count={d}
        \\residual_effect_count={d}
        \\required_host_capabilities={d}
        \\
    ,
        .{
            manifest.application_name,
            manifest.application_version,
            &application_id,
            manifest.world_application_abi_version,
            manifest.world_package_version,
            manifest.boundary_static_machine_abi_version,
            manifest.boundary_package_version,
            &root_program_id,
            manifest.internal_handler_ids.len,
            manifest.residual_effects.len,
            manifest.required_host_capabilities,
        },
    );
    for (manifest.residual_effects, 0..) |effect, index| {
        const interface_id = std.fmt.bytesToHex(effect.interface_id, .lower);
        const payload_schema_id = std.fmt.bytesToHex(effect.payload_schema_id, .lower);
        const result_schema_id = std.fmt.bytesToHex(effect.result_schema_id, .lower);
        try projection.print(
            allocator,
            \\residual_effect.{d}.interface_id={s}
            \\residual_effect.{d}.site_id={d}
            \\residual_effect.{d}.payload_schema_id={s}
            \\residual_effect.{d}.result_schema_id={s}
            \\residual_effect.{d}.authority_requirements={d}
            \\
        ,
            .{
                index,
                &interface_id,
                index,
                effect.site_id,
                index,
                &payload_schema_id,
                index,
                &result_schema_id,
                index,
                effect.authority_requirements,
            },
        );
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = projection_path,
        .data = projection.items,
    });
}
