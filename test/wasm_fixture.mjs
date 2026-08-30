const encoder = new TextEncoder();

const exportsV1 = [
  ["memory", 2, 0],
  ["boundary_process_kernel_abi_version", 0, 0],
  ["boundary_process_kernel_reserve", 0, 1],
  ["boundary_process_kernel_input_ptr", 0, 2],
  ["boundary_process_kernel_input_capacity", 0, 3],
  ["boundary_process_kernel_input_payload_ptr", 0, 4],
  ["boundary_process_kernel_occupied_memory_bytes", 0, 5],
  ["boundary_process_kernel_prepare_input", 0, 6],
  ["boundary_process_kernel_execute", 0, 7],
  ["boundary_process_kernel_output_ptr", 0, 8],
  ["boundary_process_kernel_output_len", 0, 9],
  ["boundary_process_kernel_error_ptr", 0, 10],
  ["boundary_process_kernel_error_len", 0, 11],
];

const functionTypes = [0, 1, 0, 0, 0, 2, 3, 4, 0, 2, 0, 0];

/** Build a small, engine-valid module with the complete Process ABI surface. */
export function processKernelWasmFixture(options = {}) {
  const withImport = options.withImport === true;
  const withStart = options.withStart === true;
  const wrongSignature = options.wrongSignature;
  const types = [
    funcType([], [0x7f]),
    funcType([0x7e], [0x7f]),
    funcType([], [0x7e]),
    funcType([0x7f, 0x7e, 0x7e, 0x7f, 0x7e], [0x7f]),
    funcType([0x7f], [0x7f]),
    funcType([], []),
  ];
  const assignedTypes = [...functionTypes];
  if (wrongSignature !== undefined) {
    const index = exportsV1.findIndex(([name]) => name === wrongSignature) - 1;
    if (index < 0) throw new Error("unknown fixture function " + wrongSignature);
    assignedTypes[index] = assignedTypes[index] === 2 ? 0 : 2;
  }
  if (withStart) assignedTypes.push(5);

  const sections = [section(1, vector(types))];
  if (withImport) {
    sections.push(section(2, vector([
      [...name("fixture"), ...name("imported"), 0x00, ...u32(0)],
    ])));
  }
  sections.push(section(3, vector(assignedTypes.map(u32))));

  const memoryFlags = options.memoryFlags ?? 0x01;
  const memoryType = [
    ...u32(memoryFlags),
    ...u32(options.initialPages ?? 1),
  ];
  if ((memoryFlags & 0x01) !== 0) {
    memoryType.push(...u32(options.maximumPages ?? 2));
  }
  sections.push(section(5, vector(
    Array.from({ length: options.memoryCount ?? 1 }, () => memoryType),
  )));

  const functionIndexOffset = withImport ? 1 : 0;
  let selectedExports = exportsV1.map(([exportName, kind, index]) => [
    exportName,
    kind,
    kind === 0 ? index + functionIndexOffset : index,
  ]);
  if (options.missingExport !== undefined) {
    selectedExports = selectedExports.filter(
      ([exportName]) => exportName !== options.missingExport,
    );
  }
  if (options.wrongExportKind !== undefined) {
    selectedExports = selectedExports.map(([exportName, kind, index]) =>
      exportName === options.wrongExportKind
        ? [exportName, 2, 0]
        : [exportName, kind, index]
    );
  }
  if (options.extraExport === true) {
    selectedExports.push(["future_metadata", 0, functionIndexOffset]);
  }
  if (options.duplicateExport !== undefined) {
    const duplicate = selectedExports.find(
      ([exportName]) => exportName === options.duplicateExport,
    );
    selectedExports.push([...duplicate]);
  }
  if (options.reverseExports === true) selectedExports.reverse();
  sections.push(section(7, vector(selectedExports.map(
    ([exportName, kind, index]) => [
      ...name(exportName),
      kind,
      ...u32(index),
    ],
  ))));

  if (withStart) {
    sections.push(section(8, u32(
      functionIndexOffset + assignedTypes.length - 1,
    )));
  }

  sections.push(section(10, vector(assignedTypes.map((typeIndex, index) => {
    const instruction = typeIndex === 2
      ? [0x42, 0x00]
      : typeIndex === 5
      ? []
      : [0x41, index === 0 ? 0x01 : index === 6 ? 0x28 : 0x00];
    const body = [0x00, ...instruction, 0x0b];
    return [...u32(body.length), ...body];
  }))));

  return new Uint8Array([
    0x00, 0x61, 0x73, 0x6d,
    0x01, 0x00, 0x00, 0x00,
    ...sections.flat(),
  ]);
}

function funcType(parameters, results) {
  return [0x60, ...vector(parameters.map((value) => [value])),
    ...vector(results.map((value) => [value]))];
}

function section(id, payload) {
  return [id, ...u32(payload.length), ...payload];
}

function vector(items) {
  return [...u32(items.length), ...items.flat()];
}

function name(value) {
  const bytes = encoder.encode(value);
  return [...u32(bytes.length), ...bytes];
}

function u32(value) {
  const bytes = [];
  do {
    let byte = value & 0x7f;
    value >>>= 7;
    if (value !== 0) byte |= 0x80;
    bytes.push(byte);
  } while (value !== 0);
  return bytes;
}
