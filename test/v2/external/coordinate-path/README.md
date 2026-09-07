# External coordinate-path consumer

Authored after the recorded kernel freeze. A new `coordinate-path/move`
operation takes a signed two-dimensional displacement and returns the updated
position. A shallow handler accumulates coordinates by installing its successor
with the new position as handler state. The application moves twice, yields
between moves, and returns both visited positions. Signed arithmetic is checked.

Only Boundary's public staged compiler and data APIs are imported. World checks
independent integer expectations and source semantics, transfers every saved
state among native, JavaScript and Wasmtime invocations, and compares exact
run/advance records under the previously frozen kernel bytes.
