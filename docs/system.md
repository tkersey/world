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

Dispositions bind the component-local site occurrence, not merely the Site
type. `world.systemHandle`, `world.systemMorphism`, and `world.systemExternal`
accept `site_ordinal` when one component repeats the same Site type. Bare
external Site declarations are shorthand only when the Site type identifies
one reachable occurrence across the linked graph.

At rooted component discovery, Boundary authenticates each Program once and
returns its owner-issued component projection: source identity, reachability,
canonical mappings, residual analysis, effective costs, and digests. The Link
Plan carries that admitted projection; it never trusts a structurally compatible
caller declaration or recompiles admission through repeated body lookups. Bare
external declarations are interpreted separately as morphism-target authority
and, when unique, as a source-occurrence disposition. The plan materializes
every reachable source-occurrence disposition and Failure-adapter layout before
lowering.
`System.residual_effects.items` is sized to the exact active residual count, so
inactive declarations do not survive as public capacity or undefined slots.

Internal handlers require exact `Payload == Provider.InitialArgs` and
`Resume == Provider.Result`. Provider Failure either equals the root Failure or
uses one explicit pure total `world.failureMorphism`. The resulting
`System.Program.image()` is ordinary BPI1 and contains no World runtime object.
Each non-identity provider Failure map lowers once into a shared pure Boundary
function. Dynamic failure sites call that function and retain only one local
terminal continuation; map topology therefore scales additively with map size
and call sites rather than duplicating the map at every site.
Each source component is independently admitted by Boundary before remapping;
linker-generated unit and Failure adapters occupy separate reductions so
source block instructions and authored Machine-v2 costs are preserved.
Unreachable effect declarations require no disposition and contribute no
residual authority. Handler and morphism declarations behind those occurrences
do not discover providers or enter the linked handler topology. Unreachable
helper graphs retain their original definitions, edges, and dominance; only a
terminal that becomes invalid under its linked non-root role is privatized to a
local inert loop. This includes impossible Failure terminals and unreachable
void returns; reachable void returns alone receive return adapters. A void-input
provider keeps its original entry and Control IR edges; a generated handler
wrapper owns the explicit unit call convention.

`world.application` remains a compatibility and optional-specialization path;
its manifest, Frame, provider scheduler, and application-specific WebAssembly
are not part of the portable `world.system` contract.
