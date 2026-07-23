# Dynamic Subagents

World Comptime v1 compiles every statically selected provider into its parent
application. An independently deployed child application therefore does not
cross the internal-handler boundary. It crosses the residual effect boundary
as `agent.invoke.v1`.

The request carries only application semantics:

```text
child application identity
canonical child input bytes
requested deterministic limits
```

It carries no child worker, registry handle, credential, storage path, endpoint,
or receiver authority. The parent application validates the returned
`EffectResult` against the pending request exactly as it validates every other
external result.

The receiver-selected capability owns child execution. It validates the child
artifact and local policy, creates or resumes a child run, drives the child
through a compatible world-host, and returns only the bounded child-result
projection. It cannot author the parent Frame, mutate the parent branch head,
or insert a child continuation into parent state.

The initial handler may complete the child synchronously under bounded steps or
return `deferred`. Parking remains explicit in the parent Frame. Dynamically
linking child code into a live parent, discovering providers through a runtime
registry, and silently importing child authority are outside Application ABI
v1.

Use a static World handler when the child implementation and lifecycle are part
of the application build. Use `agent.invoke.v1` when deployment identity,
receiver policy, or lifecycle ownership must remain independent.
