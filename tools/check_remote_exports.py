"""Fail if an engine does not export the bridge's native wire entry points."""
from pathlib import Path
import struct
import re

ROOT = Path(__file__).resolve().parents[1]
b = (ROOT / 'third_party/localist_remote/windows/runtime/librustdesk.dll').read_bytes()
u16 = lambda o: struct.unpack_from('<H', b, o)[0]
u32 = lambda o: struct.unpack_from('<I', b, o)[0]
pe = u32(0x3c)
sections = pe + 24 + u16(pe + 20)
def offset(rva):
    for i in range(u16(pe + 6)):
        at = sections + i * 40
        size, start, raw_size, raw = struct.unpack_from('<IIII', b, at + 8)
        if start <= rva < start + max(size, raw_size):
            return rva - start + raw
    raise ValueError('Invalid PE address')
export = offset(u32(pe + 24 + 112))
count, names = u32(export + 24), offset(u32(export + 32))
symbols = set()
for i in range(count):
    at = offset(u32(names + 4 * i))
    symbols.add(b[at:b.index(b'\0', at)].decode('ascii'))
bridge = (ROOT / 'third_party/localist_remote/lib/generated_bridge.dart').read_text(encoding='utf-8')
expected = set(re.findall(r"['\"](wire_\w+)['\"]", bridge))
expected.update({'rustdesk_core_main_args', 'free_c_args'})
missing = sorted(expected - symbols)
print(f'{len(expected)} bridge exports checked; {len(missing)} missing: {missing}')
raise SystemExit(bool(missing))
