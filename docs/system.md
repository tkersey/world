# World System Linker v1

`world.system` is the canonical portable composition path. It consumes ordinary
Boundary Programs and returns one ordinary Boundary Program:

```text
root Program + provider Programs + handlers + morphisms + external effects
  -> one closed Control IR
  -> one BPI1
```

The linker owns component ID remapping, schema interning, function and block
renumbering, handler-call construction, Failure mapping, cycle rejection, and
residual-effect calculation. Boundary still owns Control IR validation, RNF,
BPI1, and execution semantics.

Every source effect site has exactly one disposition:

```text
internal handler
effect morphism
intentionally residual external effect
```

Internal handlers require exact `Payload == Provider.InitialArgs` and
`Resume == Provider.Result`. Provider Failure either equals the root Failure or
uses one explicit pure total `world.failureMorphism`. The resulting
`System.Program.image()` is ordinary BPI1 and contains no World runtime object.

`world.application` remains a compatibility and optional-specialization path;
its manifest, Frame, provider scheduler, and application-specific WebAssembly
are not part of the portable `world.system` contract.
