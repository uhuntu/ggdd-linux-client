#!/usr/bin/env node
import { chmod, lstat, mkdir, readFile, rename, symlink, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';

const GGDD_DATA = process.env.GGDD_WINE_DATA ||
  '/home/hunt/tools/ggdd-linux-wine-dashboard-bundle/ggdd-full-wine-bundle/.wine-prefix/drive_c/users/hunt/AppData/Roaming/GGDD';
const NATIVE_MIHOMO = process.env.GGDD_NATIVE_MIHOMO ||
  '/home/hunt/tools/ggdd-linux-wine-dashboard-bundle/mihomo';
const GEODATA_DIR = process.env.GGDD_GEODATA_DIR ||
  '/home/hunt/tools/ggdd-linux-wine-dashboard-bundle/data';
const RUNTIME_DIR = process.env.GGDD_NATIVE_DATA ||
  '/home/hunt/Desktop/ggdd-linux-client/runtime';
const PROFILE_PATH = path.join(RUNTIME_DIR, 'profile.yaml');
const PROFILE_NEXT = path.join(RUNTIME_DIR, '.profile.yaml.next');
const TEST_PROFILE_PATH = path.join(RUNTIME_DIR, 'native-test.yaml');
const VENDOR_PROFILE_PATH = path.join(RUNTIME_DIR, 'vendor-profile.yaml');
const OUTBOUND_INTERFACE = process.env.GGDD_OUTBOUND_INTERFACE || 'enx00e03c3604ad';
const XOR_KEY = Buffer.from('SIzLm51puIlCewdfDWCgWXQ_Kq-ST242UBEVBhKReO7guLPFH0=', 'utf8');

function xorBytes(input, key = XOR_KEY) {
  const output = Buffer.alloc(input.length);
  for (let i = 0; i < input.length; i++) output[i] = input[i] ^ key[i % key.length];
  return output;
}

function decodeStoredJson(text) {
  return JSON.parse(xorBytes(Buffer.from(text.trim(), 'base64')).toString('utf8'));
}

// The gateway protocol XORs JavaScript string code units, then js-base64 encodes UTF-8.
function gatewayXor(text) {
  let output = '';
  const key = XOR_KEY.toString('utf8');
  for (let i = 0; i < text.length; i++) {
    output += String.fromCharCode(text.charCodeAt(i) ^ key.charCodeAt(i % key.length));
  }
  return output;
}

function gatewayEncode(text) {
  return Buffer.from(gatewayXor(text), 'utf8').toString('base64');
}

function gatewayDecode(text) {
  const binary = Buffer.from(text.trim(), 'base64').toString('utf8');
  return JSON.parse(gatewayXor(binary));
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 15000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function gatewayGet(baseUrl, apiName, authorization) {
  const endpoint = new URL(baseUrl.replace(/\/$/, '') + '/api/v1');
  endpoint.searchParams.set('api_name', gatewayEncode(apiName));
  endpoint.searchParams.set('method', 'get');
  endpoint.searchParams.set('header', JSON.stringify({ Authorization: authorization }));
  const response = await fetchWithTimeout(endpoint);
  const body = await response.text();
  if (!response.ok) throw new Error(`gateway HTTP ${response.status}`);
  const decoded = gatewayDecode(body);
  const code = decoded?.code ?? decoded?.status;
  if (![undefined, 0, '0', 200, '200', 'success'].includes(code)) {
    throw new Error(decoded?.message || decoded?.msg || `gateway business error ${code}`);
  }
  if (decoded?.data === undefined) throw new Error('gateway response has no data');
  return decoded.data;
}

async function loadState() {
  const [userText, appText] = await Promise.all([
    readFile(path.join(GGDD_DATA, 'user.yaml'), 'utf8'),
    readFile(path.join(GGDD_DATA, 'tyAppConfig.yaml'), 'utf8')
  ]);
  const user = decodeStoredJson(userText);
  const app = decodeStoredJson(appText);
  if (!user?.auth_data) throw new Error('cached GGDD login is missing or expired');
  const candidates = [app.linux_api_url1, app.linux_api_url2, app.windows_api_url1, app.windows_api_url2]
    .filter((value, index, array) => value && array.indexOf(value) === index);
  if (!candidates.length) throw new Error('no GGDD API endpoint found in cached configuration');
  return { authorization: user.auth_data, candidates };
}

async function getSubscription(state) {
  const failures = [];
  for (const baseUrl of state.candidates) {
    try {
      const subscription = await gatewayGet(baseUrl, '/user/getXorSubscribe', state.authorization);
      if (!subscription?.n_encry_subscribe_yaml) throw new Error('subscription URL missing');
      return subscription;
    } catch (error) {
      failures.push(`${new URL(baseUrl).host}: ${error.message}`);
    }
  }
  throw new Error(`all GGDD API endpoints failed: ${failures.join('; ')}`);
}

async function downloadProfile(url, authorization) {
  const response = await fetchWithTimeout(url, {
    headers: {
      Authorization: authorization,
      'User-Agent': 'MCUbPwUbXBUBKA==',
      plaform: 'JCAUKAJCQg==',
      'XY-Internal-Sub': 'd'
    }
  });
  const encrypted = await response.text();
  if (!response.ok) throw new Error(`profile HTTP ${response.status}`);
  const responseKey = response.headers.get('xy-internal-ckey');
  if (!responseKey) throw new Error('profile response key is missing');
  const yaml = xorBytes(Buffer.from(encrypted.trim(), 'base64'), Buffer.from(responseKey, 'utf8')).toString('utf8');
  if (!yaml.includes('proxies:') && !yaml.includes('proxy-providers:')) {
    throw new Error('decoded response is not a Mihomo profile');
  }
  return yaml;
}

function normalizeForNativeMihomo(yaml) {
  let normalized = yaml.replace(/^interface-name:.*\n/m, '');
  normalized = normalized.replace(
    /^(mixed-port:.*)$/m,
    `$1\ninterface-name: ${OUTBOUND_INTERFACE}`
  );
  normalized = normalized.split('\n').map((line) => {
    if (!/^\s*-\s*\{.*\btype:\s*trojan\b/.test(line) || /\bskip-cert-verify:/.test(line)) {
      return line;
    }
    return line.replace(
      /\}\s*$/,
      ', skip-cert-verify: true, client-fingerprint: chrome }'
    );
  }).join('\n');
  return normalized;
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.on('error', reject);
    child.on('close', (code) => code === 0 ? resolve(output) : reject(new Error(output.trim() || `exit ${code}`)));
  });
}

async function ensureGeodata() {
  for (const name of ['geoip.dat', 'geosite.dat', 'country.mmdb', 'geoip.metadb']) {
    const target = path.join(RUNTIME_DIR, name);
    try {
      await lstat(target);
    } catch {
      await symlink(path.join(GEODATA_DIR, name), target);
    }
  }
}

async function refresh() {
  await mkdir(RUNTIME_DIR, { recursive: true, mode: 0o700 });
  await chmod(RUNTIME_DIR, 0o700);
  await ensureGeodata();
  const state = await loadState();
  const subscription = await getSubscription(state);
  const downloadedYaml = await downloadProfile(subscription.n_encry_subscribe_yaml, state.authorization);
  const yaml = normalizeForNativeMihomo(downloadedYaml);
  await writeFile(PROFILE_NEXT, yaml, { mode: 0o600 });
  await chmod(PROFILE_NEXT, 0o600);
  await run(NATIVE_MIHOMO, ['-t', '-d', RUNTIME_DIR, '-f', PROFILE_NEXT]);
  await rename(PROFILE_NEXT, PROFILE_PATH);
  await chmod(PROFILE_PATH, 0o600);
  const nodeCount = (yaml.match(/^\s*-\s+\{?\s*name:/gm) || []).length;
  console.log(`Native profile refreshed and validated (${nodeCount} named entries).`);
  console.log(`Saved securely at ${PROFILE_PATH}`);
}

async function status() {
  try {
    const stat = await import('node:fs/promises').then((fs) => fs.stat(PROFILE_PATH));
    console.log(`Native profile exists (${stat.size} bytes, updated ${stat.mtime.toISOString()}).`);
  } catch {
    console.log('Native profile has not been created yet.');
  }
  const state = await loadState();
  console.log(`Cached login is present; ${state.candidates.length} API endpoint(s) available.`);
}

async function prepareTest() {
  let yaml = await readFile(PROFILE_PATH, 'utf8');
  yaml = yaml
    .replace(/^mixed-port:.*$/m, 'mixed-port: 19674')
    .replace(/^external-controller:.*$/m, "external-controller: '127.0.0.1:19091'")
    .replace(/^allow-lan:.*$/m, 'allow-lan: false');
  await writeFile(TEST_PROFILE_PATH, yaml, { mode: 0o600 });
  await chmod(TEST_PROFILE_PATH, 0o600);
  await run(NATIVE_MIHOMO, ['-t', '-d', RUNTIME_DIR, '-f', TEST_PROFILE_PATH]);
  console.log(`Parallel test profile prepared at ${TEST_PROFILE_PATH}`);
  console.log('Proxy: 127.0.0.1:19674; controller: 127.0.0.1:19091');
}

async function prepareVendor() {
  await prepareTest();
  const yaml = await readFile(TEST_PROFILE_PATH);
  const encrypted = xorBytes(yaml).toString('base64');
  await writeFile(VENDOR_PROFILE_PATH, encrypted, { mode: 0o600 });
  await chmod(VENDOR_PROFILE_PATH, 0o600);
  console.log(`Vendor profile prepared securely at ${VENDOR_PROFILE_PATH}`);
}

const command = process.argv[2] || 'status';
try {
  if (command === 'refresh') await refresh();
  else if (command === 'status') await status();
  else if (command === 'prepare-test') await prepareTest();
  else if (command === 'prepare-vendor') await prepareVendor();
  else throw new Error('usage: ggdd-native-refresh.mjs [status|refresh|prepare-test|prepare-vendor]');
} catch (error) {
  console.error(`GGDD native refresh failed: ${error.message}`);
  process.exitCode = 1;
}
