// Extract just the native engine from the checksum-pinned portable bundle.
// The Localist executable and source-built Flutter plugins provide its UI.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'third_party/localist_remote/UPSTREAM.json'), 'utf8'));
if (manifest.windows_native?.namespace === 'LocalistRemote') {
  throw Error('This package has a source-built Localist engine. Use build_remote_windows.ps1; upstream extraction would overwrite its isolated namespace.');
}
const input = fs.readFileSync(path.join(root, '.research/downloads/rustdesk-1.5.0-x86_64.exe'));
const sha = crypto.createHash('sha256').update(input).digest('hex');
if (sha !== '8555777215510d83d2d61c9dc984e4fcc838bd7e79f9d18a42585431f5e8bb47') {
  throw Error('Portable engine checksum mismatch.');
}
const dest = path.join(root, 'third_party/localist_remote/windows/runtime');
fs.mkdirSync(dest, {recursive: true});
let marker = -1;
while ((marker = input.indexOf('rustdesk', marker + 1)) >= 0) {
  const n = input.readUInt32BE(marker + 8);
  if (n > 0 && n < 260 && input.subarray(marker + 12, marker + 12 + n).toString().replaceAll('\\', '/').startsWith('./')) break;
}
if (marker < 0) throw Error('Native payload was not found.');
let pos = marker + 8;
let files = 0;
while (input.subarray(pos, pos + 8).toString() !== 'rustdesk') {
  const n = input.readUInt32BE(pos); pos += 4;
  const name = input.subarray(pos, pos + n).toString().replaceAll('\\', '/'); pos += n;
  const count = input.readUInt32BE(pos); pos += 4;
  const compressed = input.subarray(pos, pos + count); pos += count;
  const md5 = input.subarray(pos, pos + 32).toString(); pos += 32;
  if (name.includes('..') || path.isAbsolute(name)) throw Error('Invalid payload path.');
  // Plugin and Flutter DLLs are compiled with the Localist SDK, not extracted.
  if (/^(\.\/)?(librustdesk\.dll|dylib_virtual_display\.dll|printer_driver_adapter\.dll|RuntimeBroker_rustdesk\.exe|WindowInjection\.dll|drivers\/|usbmmidd_v2\/)/.test(name)) {
    const content = zlib.brotliDecompressSync(compressed);
    if (crypto.createHash('md5').update(content).digest('hex') !== md5) throw Error('Payload hash mismatch.');
    const out = path.resolve(dest, name);
    if (!out.startsWith(dest + path.sep)) throw Error('Unsafe output path.');
    fs.mkdirSync(path.dirname(out), {recursive:true});
    fs.writeFileSync(out, content); files++;
  }
}
console.log(`Verified and extracted ${files} native Windows engine files.`);
