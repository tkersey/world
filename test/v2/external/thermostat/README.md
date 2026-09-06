# External thermostat consumer

Authored after the recorded kernel freeze. The public staged Builder defines
`thermostat/below-setpoint`, an operation from signed temperatures to Boolean
heating requests. Its handler compares each reading with a caller-selected
setpoint. The application parks at an authored yield between two readings and
returns both decisions. It uses only Boundary's public compiler and data APIs.

The World test compares independent source semantics with signed-integer
expectations, transfers the saved state across fresh native, JavaScript and
Wasmtime invocations, and checks exact run/advance records.
