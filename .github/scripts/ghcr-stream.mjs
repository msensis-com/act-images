#!/usr/bin/env node
// Streams a filesystem snapshot into a container registry as image layers, without using local disk.
// Approach based on ChristopherHX/runner-image-blobs (MIT): GitHub-hosted runners do not have enough
// free space to build or pull a ~60GB image, so each layer is piped straight from tar to the registry.
//
//   tar -c ... | node ghcr-stream.mjs layer NAME OUT.json   gzip stdin, upload it as a blob, write its descriptor
//   node ghcr-stream.mjs manifest LAYERS.jsonl TAG...        build config from /etc/environment, push manifest
//
// Environment: IMAGE_REPO (owner/name), REGISTRY_URL (default https://ghcr.io),
//              REGISTRY_USER / REGISTRY_PASSWORD (token auth; omit for an anonymous local registry),
//              GZIP_LEVEL (default 6), IMAGE_LABEL_* are added as labels (IMAGE_LABEL_FOO_BAR -> foo.bar).

import { createHash } from 'node:crypto';
import { createGzip } from 'node:zlib';
import { PassThrough, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import fs from 'node:fs';

const REGISTRY = process.env.REGISTRY_URL ?? 'https://ghcr.io';
const REPO = (process.env.IMAGE_REPO ?? '').toLowerCase();
const USER = process.env.REGISTRY_USER ?? '';
const PASSWORD = process.env.REGISTRY_PASSWORD ?? '';
if (!REPO) throw new Error('IMAGE_REPO must be set (e.g. owner/ubuntu)');

// Registry tokens are short-lived and a layer upload can take many minutes, so fetch one per request.
async function authHeaders() {
  if (!PASSWORD) return {};
  const url = new URL('/token', REGISTRY);
  url.searchParams.set('service', 'registry.docker.io'); // what runner-image-blobs sends; accepted by ghcr.io
  url.searchParams.set('scope', `repository:${REPO}:pull,push`);
  const resp = await fetch(url, {
    headers: { Authorization: 'Basic ' + Buffer.from(`${USER}:${PASSWORD}`).toString('base64') },
  });
  if (!resp.ok) throw new Error(`token request failed: ${resp.status} ${await resp.text()}`);
  return { Authorization: `Bearer ${(await resp.json()).token}` };
}

async function request(method, url, { headers = {}, body, expect }) {
  const resp = await fetch(new URL(url, REGISTRY), {
    method,
    body,
    redirect: 'manual',
    ...(body && typeof body !== 'string' && !Buffer.isBuffer(body) ? { duplex: 'half' } : {}),
    headers: { ...(await authHeaders()), ...headers },
  });
  if (!expect.includes(resp.status)) {
    throw new Error(`${method} ${new URL(url, REGISTRY).pathname}: HTTP ${resp.status} ${await resp.text()}`);
  }
  return resp;
}

async function retry(what, fn, attempts = 5) {
  for (let i = 1; ; i++) {
    try {
      return await fn();
    } catch (err) {
      if (i >= attempts) throw err;
      console.log(`${what} failed (attempt ${i}/${attempts}): ${err.message}`);
      await new Promise((r) => setTimeout(r, 2000 * i));
    }
  }
}

const sha256 = (data) => 'sha256:' + createHash('sha256').update(data).digest('hex');
const location = (resp) => new URL(resp.headers.get('location'), REGISTRY);

// Upload a blob whose content is only known once `body` has been fully streamed.
async function uploadStream(body, finalDigest) {
  const start = await retry('start upload', () =>
    request('POST', `/v2/${REPO}/blobs/uploads/`, { body: '', expect: [202] }));
  const patched = await request('PATCH', location(start), {
    body,
    headers: { 'Content-Type': 'application/octet-stream' },
    expect: [202],
  });
  const commit = location(patched);
  commit.searchParams.set('digest', await finalDigest());
  await retry('commit upload', () => request('PUT', commit, { body: '', expect: [201] }));
}

async function uploadBuffer(buf) {
  const digest = sha256(buf);
  await retry('upload blob', async () => {
    const start = await request('POST', `/v2/${REPO}/blobs/uploads/`, { body: '', expect: [202] });
    const url = location(start);
    url.searchParams.set('digest', digest);
    await request('PUT', url, { body: buf, headers: { 'Content-Type': 'application/octet-stream' }, expect: [201] });
  });
  return { digest, size: buf.length };
}

const gib = (n) => (n / 2 ** 30).toFixed(2) + ' GiB';

async function layer(name, outFile) {
  const rawHash = createHash('sha256');
  const gzHash = createHash('sha256');
  let rawBytes = 0;
  let gzBytes = 0;
  let gzDigest;
  const tap = (hash, count) => new Transform({
    transform(chunk, _enc, cb) {
      hash.update(chunk);
      count(chunk.length);
      cb(null, chunk);
    },
  });
  const body = new PassThrough();
  const streamed = pipeline(
    process.stdin,
    tap(rawHash, (n) => { rawBytes += n; }),
    createGzip({ level: Number(process.env.GZIP_LEVEL ?? 6) }),
    tap(gzHash, (n) => { gzBytes += n; }),
    body,
  );
  const progress = setInterval(() => console.log(`${name}: read ${gib(rawBytes)}, uploaded ${gib(gzBytes)}`), 30000);
  try {
    await Promise.all([
      streamed,
      uploadStream(body, async () => {
        await streamed;
        gzDigest = 'sha256:' + gzHash.digest('hex');
        return gzDigest;
      }),
    ]);
  } finally {
    clearInterval(progress);
  }
  const descriptor = {
    name,
    diff_id: 'sha256:' + rawHash.digest('hex'),
    digest: gzDigest,
    size: gzBytes,
  };
  fs.writeFileSync(outFile, JSON.stringify(descriptor) + '\n');
  console.log(`${name}: done, ${gib(rawBytes)} -> ${gib(gzBytes)} ${descriptor.digest}`);
}

function readEnvironment() {
  const env = [];
  for (const line of fs.readFileSync('/etc/environment', 'utf8').split('\n')) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (m) env.push(`${m[1]}=${m[2].replace(/^"(.*)"$/, '$1')}`);
  }
  return env;
}

async function manifest(layersFile, tags) {
  const layers = fs.readFileSync(layersFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  if (layers.length === 0) throw new Error(`no layers in ${layersFile}`);
  const env = readEnvironment();
  const envMap = Object.fromEntries(env.map((e) => [e.slice(0, e.indexOf('=')), e.slice(e.indexOf('=') + 1)]));
  const arch = { x64: 'amd64', arm64: 'arm64' }[process.arch];
  const created = new Date().toISOString();

  const labels = {
    'org.opencontainers.image.created': created,
    'org.opencontainers.image.description': `Snapshot of the GitHub-hosted ${envMap.ImageOS ?? 'ubuntu'} runner (${arch})`,
    'org.opencontainers.image.version': envMap.ImageVersion ?? '',
  };
  for (const [k, v] of Object.entries(process.env)) {
    if (k.startsWith('IMAGE_LABEL_')) labels[k.slice(12).toLowerCase().replaceAll('_', '.')] = v;
  }

  const config = Buffer.from(JSON.stringify({
    created,
    architecture: arch,
    ...(arch === 'arm64' ? { variant: 'v8' } : {}),
    os: 'linux',
    config: {
      Env: env,
      Cmd: ['bash'],
      User: `${process.getuid()}:${process.getgid()}`,
      Labels: labels,
    },
    rootfs: { type: 'layers', diff_ids: layers.map((l) => l.diff_id) },
    history: layers.map((l) => ({ created, created_by: `tar of the hosted runner filesystem: ${l.name}` })),
  }));
  const cfg = await uploadBuffer(config);

  const body = JSON.stringify({
    schemaVersion: 2,
    mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
    config: { mediaType: 'application/vnd.docker.container.image.v1+json', ...cfg },
    layers: layers.map((l) => ({ mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: l.size, digest: l.digest })),
  });
  for (const tag of tags) {
    await retry(`push ${tag}`, () => request('PUT', `/v2/${REPO}/manifests/${tag}`, {
      body,
      headers: { 'Content-Type': 'application/vnd.docker.distribution.manifest.v2+json' },
      expect: [201],
    }));
    console.log(`pushed ${REPO}:${tag} (${layers.length} layers, ${gib(layers.reduce((s, l) => s + l.size, 0))} compressed)`);
  }
}

const [mode, ...args] = process.argv.slice(2);
if (mode === 'layer' && args.length === 2) await layer(...args);
else if (mode === 'manifest' && args.length >= 2) await manifest(args[0], args.slice(1));
else {
  console.error('usage: ghcr-stream.mjs layer NAME OUT.json < tar | ghcr-stream.mjs manifest LAYERS.jsonl TAG...');
  process.exit(2);
}
