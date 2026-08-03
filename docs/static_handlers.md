# World Machine Handlers

Status: World 2.0 implementation surface.

World handler ownership is decided at comptime. Runtime state records only the selected dense handler tag and continuation bytes; it contains no route labels, provider catalogs, or live handler objects.

## Internal machine handler

```zig
world.v1.handle(
    ParentMachine,
    site_ordinal,
    expected_site_identity,
    ProviderMachine,
)
```

The provider must be a Boundary Machine ABI v2 type whose `InitialArgs` is
exactly the handled site's `Payload` and whose `Result` exactly equals that
site's `Resume`. The parent site must be resumable. The owner Machine, ordinal,
and expected site identity jointly select the exact source occurrence.

World compiles provider invocation into:

1. encode the parked parent state;
2. initialize and push the provider state;
3. reduce the provider through static dispatch;
4. preserve both states if the provider emits an external effect;
5. resume the exact parent site when the provider completes.

The host never observes the handled parent site.

## External effect handler

```zig
world.v1.external(OwnerMachine, site_ordinal, .{
    .site_identity = "file.read.v1",
    .interface = "host.file.read.v1",
    .authority = .file_read,
    .response_mode = .resume,
})
```

An external binding contributes one residual effect to `ApplicationManifest`. World derives its interface id, Boundary site id, request and result schema ids, allowed statuses, authority requirements, and deterministic effect limits. The application validates every supplied `EffectResult` before resuming Boundary state.

## Laws

- Exact ownership: every reachable operation site has exactly one binding.
- Effect-row subtraction: an internal site is absent from the residual row.
- Static routing: runtime dispatch uses generated integer tags, never labels.
- Exact return: provider completion resumes only the request that selected that provider binding.
- Authority separation: internal handlers carry semantics; external bindings declare requirements but grant no receiver authority.

The compile-fail corpus falsifies missing, ambiguous, incompatible, cyclic, and over-depth configurations.
