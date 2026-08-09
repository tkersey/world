# Application state

A `world.protocol.v1.Frame` is the complete portable semantic state of an
application run. It binds application identity, parent identity, sequence,
machine state, pending effect, resource counters, result or failure, and its
own canonical identity.

The WASM instance owns scratch bytes only. Resetting or replacing an instance
cannot advance or rewind a run; continuation always consumes canonical Frame
bytes plus an optional validated EffectResult.
