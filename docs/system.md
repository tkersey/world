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

At rooted component discovery, Boundary authenticates each Program and returns
its owner-issued component projection: source identity, reachability, canonical
mappings, residual analysis, effective costs, and digests. World admits one
component instance per `(Program, effective Failure map)` key: equal keys share
one instance, while distinct handler-occurrence maps retain distinct instances.
The Link Plan carries each admitted projection; it never trusts a structurally
compatible caller declaration or recompiles admission through repeated body
lookups. Bare external declarations are interpreted separately as
morphism-target authority and, when unique, as a source-occurrence disposition.
The plan materializes
every reachable source-occurrence disposition, each effective Failure map and
its quotient projection, each per-site Failure-adapter kind, every shared
direct-adapter owner, and every dynamic-selector owner before lowering.
`System.residual_effects.items` is sized to the exact active residual count, so
inactive declarations do not survive as public capacity or undefined slots.
Types satisfying Boundary's `Payload` / `Resume` / `semantic_identity` Site
interface always follow the bare-Site path, regardless of extra declarations.
Other external entries are occurrence wrappers only when they provide
`Consumer`, `Site`, and `site_ordinal`.
Distinct residual occurrences must also have distinct Boundary semantic
identities; v1 rejects duplicate effective identities before BPI1 emission.

Internal handlers require exact `Payload == Provider.InitialArgs` and
`Resume == Provider.Result`. Provider Failure either equals the root Failure or
uses one explicit pure total `world.failureMorphism`. The resulting
`System.Program.image()` is ordinary BPI1 and contains no World runtime object.
Each distinct multi-tag provider Failure map used by dynamic failure sites
lowers once into one pure selection-block Boundary function shared across
providers with the same source type, target type, source tags, and mapped
targets. Dynamic sites call that function and retain one local terminal
continuation; quotient-size-one maps remain O(1) direct
specializations. Identical direct failures share one adapter per source
function and mapped target. Mapping blocks therefore scale with semantic
owners, not source occurrences or map cardinality.
Each source component is independently admitted by Boundary before remapping;
linker-generated unit and Failure adapters occupy separate reductions so
source block instructions and authored Machine-v2 costs are preserved.
When a provider uses a distinct Failure type, each block interns the mapped
root-Failure targets required by its fallible instructions. Boundary component
admission normalizes evaluator-v1 role defaults and evaluator-v2 authored
Failure constants to one ordinary-operand-count plus effective-tag projection;
World preserves an unchanged suffix or replaces it exactly once through the
declared morphism. Generated constant
instructions make those targets available once per block, and evaluator
semantics v2 appends them to each fallible instruction in Boundary role order.
Instruction-originated failures therefore pass through the same declared total
Failure morphism as explicit `fail` and `fail_value` terminals. The generated
constants add only their exact minimum to the optional Machine-v2 compatibility
cost; Process execution remains fuel-free.
Programs with retained nonempty handler or morphism declarations are rejected as
source components. A linked Program whose generated binding rows are empty may
be admitted as an ordinary Boundary Program; general recursive relinking is not
a World v1 guarantee.
Unreachable effect declarations require no disposition and contribute no
residual authority. Handler and morphism declarations behind those occurrences
do not discover providers or enter the linked handler topology. Unreachable
helper graphs may be source-normalized where the linked root types or function
roles require it; they are absent from RNF/BPI1 and carry no runtime semantics.
This includes Failure instructions and terminals, impossible Failure terminals,
and unreachable void returns; reachable void returns alone receive return
adapters. A void-input
provider keeps its original entry and Control IR edges; all reachable void exits
share one component-local unit-return adapter, and a generated handler wrapper
owns the explicit unit call convention.

`world.application` remains a compatibility and optional-specialization path;
its manifest, Frame, provider scheduler, and application-specific WebAssembly
are not part of the portable `world.system` contract.
