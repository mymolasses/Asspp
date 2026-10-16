// Independent Web Crypto oracle for the AssppWeb PBKDF2/AES-GCM wire format.
import { webcrypto } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import assert from 'node:assert/strict';
const { subtle } = webcrypto;
const [mode, directory] = process.argv.slice(2);
const password = 'test-密码🔑';
const account = {
  email: 'fixture@example.com', password: 'fixture-only-password', appleId: 'fixture@example.com',
  store: '143441-1,29', firstName: 'Test', lastName: 'Fixture', passwordToken: 'fixture-only-token',
  directoryServicesIdentifier: '123456', deviceIdentifier: 'AABBCCDDEEFF', pod: '25',
  cookies: [{ name: 'fixture-cookie', value: 'fixture-value', path: '/', domain: '.apple.com',
    expiresAt: 2100000000, httpOnly: true, secure: true }],
};
async function key(salt) {
  const material = await subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
  return subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' }, material,
    { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}
async function encrypt(value) {
  const salt = webcrypto.getRandomValues(new Uint8Array(16));
  const iv = webcrypto.getRandomValues(new Uint8Array(12));
  const bytes = await subtle.encrypt({ name: 'AES-GCM', iv }, await key(salt), new TextEncoder().encode(JSON.stringify(value)));
  return Buffer.concat([salt, iv, Buffer.from(bytes)]).toString('base64');
}
if (mode === 'prepare') {
  const payload = { format: 'asspp.accounts', version: 1, accounts: [account] };
  await writeFile(join(directory, 'payload.json'), JSON.stringify(payload));
  await writeFile(join(directory, 'web.enc'), await encrypt(payload));
  await writeFile(join(directory, 'legacy.enc'), await encrypt([account]));
} else if (mode === 'verify') {
  const bytes = Buffer.from(await readFile(join(directory, 'native.enc'), 'utf8'), 'base64');
  const plaintext = await subtle.decrypt({ name: 'AES-GCM', iv: bytes.subarray(16, 28) },
    await key(bytes.subarray(0, 16)), bytes.subarray(28));
  const payload = JSON.parse(new TextDecoder().decode(plaintext));
  assert.equal(payload.format, 'asspp.accounts');
  assert.equal(payload.version, 1);
  assert.deepEqual(payload.accounts, [account]);
  console.log('PASS: native backup decrypts in Web Crypto with all account fields intact');
} else { throw new Error('Expected prepare or verify'); }
