import { chromium, devices } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');
const reportRoot = path.join(repoRoot, 'reports');

const config = {
  webUrl: process.env.WEB_URL || 'https://pos-labs.vercel.app/',
  apiUrl: process.env.API_URL || 'https://pos-labs.onrender.com',
  headless: process.env.HEADLESS !== 'false',
  timeoutMs: Number(process.env.STEP_TIMEOUT_MS || 70000),
  tag:
    process.env.PERF_TAG ||
    `PERFTEST-${new Date().toISOString().replace(/[-:]/g, '').slice(0, 13)}`,
  pos: {
    username: process.env.POS_USER || 'pos1',
    password: process.env.POS_PASS || 'pos123456',
    branchId: process.env.POS_BRANCH_ID || '00000',
    posId: process.env.POS_ID || 'POS001',
    posSecret: process.env.POS_SECRET || 'default_if_needed',
  },
  hq: {
    username: process.env.HQ_USER || 'hqmanager',
    password: process.env.HQ_PASS || 'hq123456',
  },
  admin: {
    username: process.env.ADMIN_USER || 'admin',
    password: process.env.ADMIN_PASS || 'admin123',
  },
};

const bravePath = '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser';
const endpointSlaMs = {
  dialogOrList: 1000,
  scanToCart: 1000,
  payment: 2000,
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const iso = () => new Date().toISOString();

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function safeName(value) {
  return String(value).replace(/[^a-z0-9._-]+/gi, '-').replace(/^-+|-+$/g, '');
}

function ms(value) {
  if (value == null || Number.isNaN(value)) return null;
  return Math.round(value);
}

function parseJsonMaybe(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function unwrap(payload) {
  if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
    if (payload.data && typeof payload.data === 'object') return payload.data;
    if (payload.bill && typeof payload.bill === 'object') return payload.bill;
    if (payload.part && typeof payload.part === 'object') return payload.part;
  }
  return payload;
}

function listFrom(payload) {
  if (Array.isArray(payload)) return payload;
  if (!payload || typeof payload !== 'object') return [];
  for (const key of ['data', 'items', 'bills', 'parts', 'returns', 'results']) {
    if (Array.isArray(payload[key])) return payload[key];
  }
  return [];
}

function billItems(bill) {
  return listFrom({ data: bill?.items || bill?.details || bill?.billItems || [] });
}

class PerfHarness {
  constructor() {
    this.steps = [];
    this.requests = [];
    this.pending = new Map();
    this.cdpPending = new Map();
    this.tokens = {};
    this.users = {};
    this.created = {
      bills: [],
      transfers: [],
      members: [],
      stockCounts: [],
      dailyCloses: [],
      returns: [],
    };
    this.products = [];
    this.browser = null;
    this.context = null;
    this.pages = {};
    this.startedAt = iso();
    this.reportId = `pos-full-day-perf-${this.startedAt.replace(/[-:]/g, '').slice(0, 13)}`;
    this.evidenceDir = path.join(reportRoot, this.reportId);
  }

  async init() {
    ensureDir(this.evidenceDir);
    const launch = {
      headless: config.headless,
    };
    if (fs.existsSync(bravePath)) {
      launch.executablePath = bravePath;
    }
    this.browser = await chromium.launch(launch);
    this.context = await this.browser.newContext({
      ...devices['iPhone 13'],
      locale: 'th-TH',
      timezoneId: 'Asia/Bangkok',
      recordHar: {
        path: path.join(this.evidenceDir, 'network.har'),
        mode: 'minimal',
      },
    });
  }

  async close() {
    await this.context?.close().catch(() => {});
    await this.browser?.close().catch(() => {});
  }

  async page(actor) {
    if (this.pages[actor]) return this.pages[actor];
    const page = await this.context.newPage();
    page.setDefaultTimeout(config.timeoutMs);
    page.on('request', (req) => this.onRequest(actor, req));
    page.on('response', (res) => this.onResponse(res));
    page.on('requestfailed', (req) => this.onRequestFailed(req));
    await this.attachCdpPreflightCapture(page, actor);
    this.pages[actor] = page;
    await page.goto(config.webUrl, { waitUntil: 'domcontentloaded', timeout: config.timeoutMs });
    return page;
  }

  async attachCdpPreflightCapture(page, actor) {
    try {
      const client = await this.context.newCDPSession(page);
      await client.send('Network.enable');
      client.on('Network.requestWillBeSent', (event) => {
        const url = event.request?.url || '';
        const method = event.request?.method || '';
        if (method !== 'OPTIONS' || !url.startsWith(config.apiUrl)) return;
        const entry = {
          id: `${this.requests.length + 1}`,
          actor,
          method,
          url,
          path: url.slice(config.apiUrl.length) || '/',
          type: 'preflight',
          source: 'cdp',
          startedAtEpochMs: Date.now(),
          startedAt: iso(),
          status: null,
          durationMs: null,
          failure: null,
        };
        this.cdpPending.set(event.requestId, entry);
        this.requests.push(entry);
      });
      client.on('Network.responseReceived', (event) => {
        const entry = this.cdpPending.get(event.requestId);
        if (!entry) return;
        entry.status = event.response?.status || null;
      });
      client.on('Network.loadingFinished', (event) => {
        const entry = this.cdpPending.get(event.requestId);
        if (!entry) return;
        entry.durationMs = Date.now() - entry.startedAtEpochMs;
        this.cdpPending.delete(event.requestId);
      });
      client.on('Network.loadingFailed', (event) => {
        const entry = this.cdpPending.get(event.requestId);
        if (!entry) return;
        entry.durationMs = Date.now() - entry.startedAtEpochMs;
        entry.failure = event.errorText || 'request_failed';
        this.cdpPending.delete(event.requestId);
      });
    } catch {
      // CDP is Chromium-only. The regular Playwright network listener remains active.
    }
  }

  onRequest(actor, req) {
    const url = req.url();
    if (!url.startsWith(config.apiUrl)) return;
    const entry = {
      id: `${this.requests.length + 1}`,
      actor,
      method: req.method(),
      url,
      path: url.slice(config.apiUrl.length) || '/',
      type: req.resourceType(),
      startedAtEpochMs: Date.now(),
      startedAt: iso(),
      status: null,
      durationMs: null,
      failure: null,
    };
    this.pending.set(req, entry);
    this.requests.push(entry);
  }

  async onResponse(res) {
    const req = res.request();
    const entry = this.pending.get(req);
    if (!entry) return;
    entry.status = res.status();
    entry.durationMs = Date.now() - entry.startedAtEpochMs;
    entry.responseSize = Number(res.headers()['content-length'] || 0) || null;
  }

  onRequestFailed(req) {
    const entry = this.pending.get(req);
    if (!entry) return;
    entry.durationMs = Date.now() - entry.startedAtEpochMs;
    entry.failure = req.failure()?.errorText || 'request_failed';
  }

  async screenshot(actor, label) {
    const page = await this.page(actor);
    const file = path.join(this.evidenceDir, `${safeName(actor)}-${safeName(label)}.png`);
    await page.screenshot({ path: file, fullPage: true }).catch(() => {});
    return path.relative(repoRoot, file);
  }

  async step(meta, fn) {
    const startedAtEpochMs = Date.now();
    const startedAt = iso();
    const requestStart = this.requests.length;
    let result = null;
    let error = null;
    try {
      result = await fn();
    } catch (err) {
      error = err;
    }
    await sleep(100);
    const endedAtEpochMs = Date.now();
    const endpoints = this.requests
      .slice(requestStart)
      .map((r) => ({
        method: r.method,
        path: r.path,
        status: r.status,
        durationMs: ms(r.durationMs),
        type: r.type,
        failure: r.failure,
      }));
    const firstRequest = this.requests
      .slice(requestStart)
      .find((r) => r.method !== 'OPTIONS');
    const notes = this.analyzeStep(meta, endpoints, result, error);
    const allowedStatuses = new Set(meta.allowedStatuses || result?.allowedStatuses || []);
    const failedEndpoint = endpoints.find(
      (e) => (e.status && e.status >= 400 && !allowedStatuses.has(e.status)) || e.failure,
    );
    const step = {
      actor: meta.actor,
      flow: meta.flow,
      action: meta.action,
      startedAt,
      durationMs: endedAtEpochMs - startedAtEpochMs,
      firstRequestMs: firstRequest ? firstRequest.startedAtEpochMs - startedAtEpochMs : null,
      uiUpdateMs: result?.uiUpdateMs ?? null,
      requestCount: endpoints.filter((e) => e.method !== 'OPTIONS').length,
      preflightCount: endpoints.filter((e) => e.method === 'OPTIONS').length,
      endpoints,
      status: error || failedEndpoint ? 'fail' : notes.some((n) => n.startsWith('SLA')) ? 'slow' : 'pass',
      evidenceIds: result?.evidenceIds || [],
      screenshots: result?.screenshots || [],
      pass: !error && !failedEndpoint && !notes.some((n) => n.startsWith('SLA')),
      bottleneckNotes: notes,
      error: error ? String(error.message || error) : null,
      data: result?.data,
    };
    this.steps.push(step);
    const statusIcon = step.status === 'pass' ? 'PASS' : step.status.toUpperCase();
    console.log(`[${statusIcon}] ${meta.actor}/${meta.flow}/${meta.action} ${step.durationMs}ms`);
    if (error) console.log(`  error: ${step.error}`);
    return step;
  }

  analyzeStep(meta, endpoints, result, error) {
    const notes = [];
    if (error) notes.push(`ERROR: ${String(error.message || error)}`);
    for (const e of endpoints) {
      if (e.status && e.status >= 400 && !(meta.allowedStatuses || result?.allowedStatuses || []).includes(e.status)) {
        notes.push(`HTTP ${e.status}: ${e.method} ${e.path}`);
      }
      if (e.failure) notes.push(`NETWORK: ${e.method} ${e.path} ${e.failure}`);
      if (e.durationMs > endpointSlaMs.dialogOrList && /\/parts\/search|\/parts|\/bills|\/transfers|\/stock-counts|\/daily-closes|\/cash-reconciliations/.test(e.path)) {
        notes.push(`SLA list/API >1s: ${e.method} ${e.path} ${e.durationMs}ms`);
      }
      if (/payment/.test(e.path) && e.durationMs > endpointSlaMs.payment) {
        notes.push(`SLA payment >2s: ${e.method} ${e.path} ${e.durationMs}ms`);
      }
      if (/add-item-by-barcode/.test(e.path) && e.durationMs > endpointSlaMs.scanToCart) {
        notes.push(`SLA scan mutation >1s: ${e.method} ${e.path} ${e.durationMs}ms`);
      }
    }
    const total = endpoints.reduce((sum, e) => sum + (e.durationMs || 0), 0);
    const preflight = endpoints
      .filter((e) => e.method === 'OPTIONS')
      .reduce((sum, e) => sum + (e.durationMs || 0), 0);
    if (total > 0 && preflight / total > 0.2) {
      notes.push(`CORS preflight >20% of step network time (${Math.round((preflight / total) * 100)}%)`);
    }
    if (meta.analysis === 'scan' && result?.firstRequestAfterSubmitMs != null) {
      if (result.firstRequestAfterSubmitMs > 100) {
        notes.push(`SLA first request after Enter >100ms: ${result.firstRequestAfterSubmitMs}ms`);
      }
      if (result.scanRequestCount > 1) {
        notes.push(`Frontend scan request regression: ${result.scanRequestCount} non-preflight requests`);
      }
    }
    return [...new Set(notes)];
  }

  async browserFetch(actor, method, apiPath, token, body = undefined, options = {}) {
    const page = await this.page(actor);
    return page.evaluate(
      async ({ apiUrl, apiPath, method, token, body, timeoutMs }) => {
        const started = performance.now();
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
          const headers = {};
          if (token) headers.Authorization = `Bearer ${token}`;
          if (body !== undefined) headers['Content-Type'] = 'application/json';
          const res = await fetch(`${apiUrl}${apiPath}`, {
            method,
            headers,
            body: body === undefined ? undefined : JSON.stringify(body),
            signal: controller.signal,
          });
          const text = await res.text();
          let json = null;
          try {
            json = text ? JSON.parse(text) : null;
          } catch (_) {}
          return {
            ok: res.ok,
            status: res.status,
            durationMs: Math.round(performance.now() - started),
            text,
            json,
          };
        } catch (error) {
          return {
            ok: false,
            status: 0,
            durationMs: Math.round(performance.now() - started),
            error: String(error?.message || error),
          };
        } finally {
          clearTimeout(timer);
        }
      },
      {
        apiUrl: config.apiUrl,
        apiPath,
        method,
        token,
        body,
        timeoutMs: options.timeoutMs || config.timeoutMs,
      },
    );
  }

  async api(actor, method, apiPath, token, body, options = {}) {
    const res = await this.browserFetch(actor, method, apiPath, token, body, options);
    if (!options.allowFailure && !res.ok) {
      throw new Error(`${method} ${apiPath} failed: ${res.status} ${res.text || res.error || ''}`);
    }
    return res;
  }

  async login(actor, credentials) {
    const body = {
      username: credentials.username,
      password: credentials.password,
      branchId: config.pos.branchId,
      posId: config.pos.posId,
      posSecret: config.pos.posSecret,
    };
    const login = await this.api(actor, 'POST', '/auth/login', null, body);
    const token = login.json?.token || login.json?.data?.token;
    if (!token) throw new Error(`missing token for ${actor}`);
    this.tokens[actor] = token;
    const me = await this.api(actor, 'GET', '/auth/me', token);
    this.users[actor] = unwrap(me.json);
    return { data: { roleId: this.users[actor]?.roleId || this.users[actor]?.role_id } };
  }

  async getOrCreateBill(actor = 'pos') {
    const token = this.tokens[actor];
    const created = await this.api(actor, 'POST', '/bills', token, {}, { allowFailure: true });
    let billId = unwrap(created.json)?.id || created.json?.existingBillId;
    if (created.status === 409) {
      billId = created.json?.existingBillId;
    }
    if (!billId) {
      const list = await this.api(actor, 'GET', '/bills?limit=1&offset=0&scope=pos&statuses=new&includeDetails=true', token);
      billId = listFrom(list.json)[0]?.id;
    }
    if (!billId) throw new Error('unable to create or recover active bill');
    const bill = await this.api(actor, 'GET', `/bills/${encodeURIComponent(billId)}`, token);
    if (!this.created.bills.includes(billId)) this.created.bills.push(billId);
    return unwrap(bill.json);
  }

  async discoverProducts() {
    const found = [];
    for (let i = 1; i <= 60 && found.length < 10; i += 1) {
      const code = `P${String(i).padStart(4, '0')}`;
      const res = await this.api('pos', 'GET', `/parts/${code}`, this.tokens.pos, undefined, { allowFailure: true, timeoutMs: 20000 });
      if (!res.ok) continue;
      const part = unwrap(res.json);
      const addresses = listFrom({ data: part?.addresses || [] });
      const vehicle = addresses.find((addr) => {
        const storeId = addr?.store?.id || addr?.storeId || addr?.store_id;
        return storeId === `vehicle_${config.pos.posId}` && Number(addr?.qty || 0) > 0;
      });
      const barcode = part?.barCode || part?.barcode;
      if (vehicle && barcode) {
        found.push({
          code: part.code || code,
          barcode,
          addressCode: vehicle.code || vehicle.addressCode,
          vehicleQty: Number(vehicle.qty || 0),
        });
      }
    }
    if (!found.length) throw new Error('no vehicle-stock products discovered');
    while (found.length < 10) found.push(found[found.length % Math.max(found.length, 1)]);
    this.products = found.slice(0, 10);
    return { data: { products: this.products } };
  }

  async uiLoginAndScan() {
    const page = await this.page('pos-ui');
    await page.goto(config.webUrl, { waitUntil: 'networkidle', timeout: config.timeoutMs });
    const vw = page.viewportSize()?.width || 390;
    const vh = page.viewportSize()?.height || 844;

    await page.mouse.click(vw * 0.5, vh * 0.412);
    await page.keyboard.type(config.pos.username, { delay: 20 });
    await page.mouse.click(vw * 0.5, vh * 0.510);
    await page.keyboard.type(config.pos.password, { delay: 20 });
    await page.mouse.click(vw * 0.5, vh * 0.612);
    await page.waitForTimeout(8000);

    // If pending bill dialog appears, continue it. If not, this harmlessly clicks inside the page.
    await page.mouse.click(vw * 0.68, vh * 0.77);
    await page.waitForTimeout(1000);

    const beforeRequests = this.requests.length;
    const barcode = this.products[0]?.barcode || '8850000001';
    await page.mouse.click(vw * 0.38, vh * 0.930);
    await page.keyboard.type(barcode, { delay: 15 });
    const submitEpoch = Date.now();
    await page.keyboard.press('Enter');
    await page.waitForTimeout(16000);
    const screenshot = await this.screenshot('pos-ui', 'ui-scan-after');
    const scanRequests = this.requests
      .slice(beforeRequests)
      .filter((r) => r.url.startsWith(config.apiUrl));
    const firstNonOptions = scanRequests.find((r) => r.method !== 'OPTIONS');
    return {
      screenshots: [screenshot],
      data: {
        barcode,
        firstRequestAfterSubmitMs: firstNonOptions ? firstNonOptions.startedAtEpochMs - submitEpoch : null,
        scanRequestCount: scanRequests.filter((r) => r.method !== 'OPTIONS').length,
      },
      firstRequestAfterSubmitMs: firstNonOptions ? firstNonOptions.startedAtEpochMs - submitEpoch : null,
      scanRequestCount: scanRequests.filter((r) => r.method !== 'OPTIONS').length,
    };
  }

  async addByBarcode(actor, billId, barcode, qty = 1) {
    return this.api(actor, 'PUT', `/bills/${billId}/add-item-by-barcode`, this.tokens[actor], { barcode, qty });
  }

  async run() {
    await this.init();

    await this.step({ actor: 'public', flow: 'baseline', action: 'frontend_load' }, async () => {
      const page = await this.page('public');
      const screenshot = await this.screenshot('public', 'frontend-load');
      return { screenshots: [screenshot] };
    });

    for (const p of ['/health', '/ready', '/test']) {
      await this.step({ actor: 'public', flow: 'baseline', action: p }, () =>
        this.api('public', 'GET', p, null, undefined, { allowFailure: true, timeoutMs: 70000 }).then((r) => ({ data: { status: r.status } })),
      );
    }

    await this.step({ actor: 'pos', flow: 'auth', action: 'login_pos1' }, () => this.login('pos', config.pos));
    await this.step({ actor: 'hqmanager', flow: 'auth', action: 'login_hqmanager' }, () => this.login('hqmanager', config.hq));
    await this.step({ actor: 'admin', flow: 'auth', action: 'login_admin' }, () => this.login('admin', config.admin));

    await this.step({ actor: 'pos', flow: 'baseline', action: 'pending_bill_recovery' }, () =>
      this.api('pos', 'GET', '/bills?limit=1&offset=0&scope=pos&statuses=new&includeDetails=true', this.tokens.pos).then((r) => ({ data: { count: listFrom(r.json).length } })),
    );

    await this.step({ actor: 'pos', flow: 'baseline', action: 'parts_search_regression_probe' }, () =>
      this.api('pos', 'GET', '/parts/search?limit=45&offset=0', this.tokens.pos, undefined, { allowFailure: true, timeoutMs: 70000 }).then((r) => ({ data: { status: r.status } })),
    );

    await this.step({ actor: 'pos', flow: 'setup', action: 'discover_10_vehicle_stock_barcodes' }, () => this.discoverProducts());

    let activeBill = null;
    await this.step({ actor: 'pos', flow: 'sales', action: 'create_or_recover_active_bill', allowedStatuses: [409] }, async () => {
      activeBill = await this.getOrCreateBill('pos');
      return { data: { billId: activeBill?.id || activeBill?.billId } };
    });
    const activeBillId = activeBill?.id || activeBill?.billId;

    await this.step({ actor: 'pos-ui', flow: 'sales', action: 'mobile_ui_scan_one_barcode', analysis: 'scan' }, () => this.uiLoginAndScan());

    await this.step({ actor: 'pos', flow: 'sales', action: 'scanner_burst_10_barcodes', analysis: 'scan' }, async () => {
      const started = Date.now();
      const results = [];
      for (const product of this.products) {
        const res = await this.addByBarcode('pos', activeBillId, product.barcode, 1);
        results.push({ barcode: product.barcode, status: res.status, durationMs: res.durationMs });
      }
      const bill = await this.api('pos', 'GET', `/bills/${activeBillId}`, this.tokens.pos);
      return {
        uiUpdateMs: Date.now() - started,
        data: {
          billId: activeBillId,
          added: results,
          itemCount: unwrap(bill.json)?.itemCount,
          totalQty: unwrap(bill.json)?.totalQty,
        },
      };
    });

    await this.step({ actor: 'pos', flow: 'sales', action: 'discount_preset_10_percent' }, () =>
      this.api('pos', 'PUT', `/bills/${activeBillId}/add-discount`, this.tokens.pos, { unit: 'percentage', amount: 10 }).then((r) => ({ data: { status: r.status } })),
    );

    const phone = `09${String(Date.now()).slice(-8)}`;
    let memberAvailable = false;
    await this.step({ actor: 'pos', flow: 'sales', action: 'member_register' }, async () => {
      const res = await this.api('pos', 'POST', '/members', this.tokens.pos, {
        name: `${config.tag} Member`,
        phone,
        email: `${config.tag.toLowerCase()}@example.test`,
        points: 0,
      });
      const member = unwrap(res.json);
      if (member?.id) this.created.members.push(member.id);
      memberAvailable = true;
      return { data: { memberId: member?.id, phone } };
    });

    await this.step({ actor: 'admin', flow: 'sales', action: 'member_seed_fallback_for_attach' }, async () => {
      if (memberAvailable) return { data: { skipped: true, reason: 'pos member registration succeeded' } };
      const res = await this.api('admin', 'POST', '/members', this.tokens.admin, {
        name: `${config.tag} Member`,
        phone,
        email: `${config.tag.toLowerCase()}@example.test`,
        points: 0,
      }, { allowFailure: true });
      const member = unwrap(res.json);
      if (res.ok && member?.id) {
        this.created.members.push(member.id);
        memberAvailable = true;
      }
      return { data: { memberId: member?.id, phone, status: res.status, fallback: true } };
    });

    await this.step({ actor: 'pos', flow: 'sales', action: 'attach_member_to_bill' }, () =>
      this.api('pos', 'PUT', `/bills/${activeBillId}/add-member-by-phone`, this.tokens.pos, { phone }).then((r) => ({ data: { status: r.status } })),
    );

    let paidBillId = activeBillId;
    await this.step({ actor: 'pos', flow: 'sales', action: 'payment_cash', analysis: 'payment' }, () =>
      this.api('pos', 'PUT', `/bills/${activeBillId}/payment`, this.tokens.pos, {
        paymentMethod: 'cash',
        paymentMeta: { type: 'cash', receivedAmount: 999999, totalAmount: unwrap(activeBill)?.totalAmount },
      }).then((r) => {
        paidBillId = unwrap(r.json)?.id || unwrap(r.json)?.billId || activeBillId;
        return { data: { billId: paidBillId, status: unwrap(r.json)?.status } };
      }),
    );

    let transferBill = null;
    await this.step({ actor: 'pos', flow: 'sales', action: 'qr_transfer_payment' }, async () => {
      transferBill = await this.getOrCreateBill('pos');
      const billId = transferBill?.id || transferBill?.billId;
      await this.addByBarcode('pos', billId, this.products[0].barcode, 1);
      const res = await this.api('pos', 'PUT', `/bills/${billId}/payment`, this.tokens.pos, { paymentMethod: 'bank' });
      return { data: { billId, status: unwrap(res.json)?.status } };
    });

    await this.step({ actor: 'pos', flow: 'sales', action: 'return_from_test_bill' }, async () => {
      const ref = await this.api('pos', 'GET', `/returns/reference/${paidBillId}`, this.tokens.pos, undefined, { allowFailure: true });
      if (!ref.ok) return { data: { skipped: true, status: ref.status, reason: 'reference bill unavailable' } };
      const reference = unwrap(ref.json);
      const item = billItems(reference)[0];
      if (!item) return { data: { skipped: true, reason: 'no returnable line' } };
      const line = {
        partCode: item.partCode || item.code,
        addressCode: item.addressCode,
        qty: 1,
        unitPrice: Number(item.price || item.unitPrice || 0),
      };
      const ret = await this.api('pos', 'POST', '/returns', this.tokens.pos, {
        referenceBillId: paidBillId,
        settlementMode: 'cash_refund',
        paymentMethod: 'cash',
        lines: [line],
      });
      const note = unwrap(ret.json);
      if (note?.id) this.created.returns.push(note.id);
      return { data: { returnId: note?.id } };
    });

    await this.step({ actor: 'pos', flow: 'sales', action: 'hold_resume_delete_bill' }, async () => {
      const bill = await this.getOrCreateBill('pos');
      const billId = bill?.id || bill?.billId;
      await this.addByBarcode('pos', billId, this.products[0].barcode, 1);
      const held = await this.api('pos', 'PUT', `/bills/${billId}/hold`, this.tokens.pos);
      const resumed = await this.api('pos', 'PUT', '/bills/switch', this.tokens.pos, { targetBillId: billId }, { allowFailure: true });
      const deleted = await this.api('pos', 'DELETE', `/bills/${billId}`, this.tokens.pos, undefined, { allowFailure: true });
      return { data: { billId, held: held.status, resumed: resumed.status, deleted: deleted.status } };
    });

    await this.step({ actor: 'hqmanager', flow: 'inventory', action: 'hq_created_transfer_create' }, async () => {
      const product = this.products[0];
      const res = await this.api('hqmanager', 'POST', '/transfers', this.tokens.hqmanager, {
        fromBranchId: config.pos.branchId,
        toBranchId: config.pos.branchId,
        notes: `${config.tag} HQ-created transfer`,
        items: [{ partCode: product.code, requestedQty: 1 }],
      });
      const transfer = unwrap(res.json);
      if (transfer?.id) this.created.transfers.push(transfer.id);
      return { data: { transferId: transfer?.id, status: transfer?.status } };
    });
    const hqTransferId = this.created.transfers.at(-1);

    await this.step({ actor: 'admin', flow: 'inventory', action: 'hq_created_transfer_approve_dispatch' }, async () => {
      if (!hqTransferId) throw new Error('missing HQ transfer id');
      const product = this.products[0];
      const approved = await this.api('admin', 'PUT', `/transfers/${hqTransferId}/approve`, this.tokens.admin, undefined, { allowFailure: true });
      const dispatched = await this.api('admin', 'PUT', `/transfers/${hqTransferId}/dispatch`, this.tokens.admin, {
        items: [{ partCode: product.code, dispatchedQty: 1 }],
      }, { allowFailure: true });
      return { data: { transferId: hqTransferId, approved: approved.status, dispatched: dispatched.status } };
    });

    await this.step({ actor: 'pos', flow: 'inventory', action: 'hq_created_transfer_receive' }, async () => {
      if (!hqTransferId) throw new Error('missing HQ transfer id');
      const product = this.products[0];
      const received = await this.api('pos', 'PUT', `/transfers/${hqTransferId}/receive`, this.tokens.pos, {
        items: [{ partCode: product.code, receivedQty: 1 }],
      }, { allowFailure: true });
      return { data: { transferId: hqTransferId, received: received.status } };
    });

    await this.step({ actor: 'pos', flow: 'inventory', action: 'pos_requisition_create_submit' }, async () => {
      const product = this.products[0];
      const created = await this.api('pos', 'POST', '/transfers/pos-restock', this.tokens.pos, {
        notes: `${config.tag} POS requisition`,
        items: [{ partCode: product.code, requestedQty: 1 }],
      });
      const transfer = unwrap(created.json);
      if (transfer?.id) this.created.transfers.push(transfer.id);
      const submitted = await this.api('pos', 'PUT', `/transfers/${transfer.id}/submit`, this.tokens.pos, undefined, { allowFailure: true });
      return { data: { transferId: transfer.id, created: created.status, submitted: submitted.status } };
    });
    const requisitionId = this.created.transfers.at(-1);

    await this.step({ actor: 'hqmanager', flow: 'inventory', action: 'pos_requisition_approve_restock' }, async () => {
      if (!requisitionId) throw new Error('missing requisition id');
      const approved = await this.api('hqmanager', 'PUT', `/transfers/${requisitionId}/approve-restock`, this.tokens.hqmanager, undefined, { allowFailure: true });
      return { data: { transferId: requisitionId, approved: approved.status } };
    });

    let stockCountId = null;
    await this.step({ actor: 'pos', flow: 'day_end', action: 'stock_count_create_save_submit' }, async () => {
      const created = await this.api('pos', 'POST', '/stock-counts', this.tokens.pos, {
        branchId: config.pos.branchId,
        notes: `${config.tag} stock count`,
      }, { allowFailure: true });
      if (!created.ok) return { data: { created: created.status } };
      const stockCount = unwrap(created.json);
      stockCountId = stockCount?.id;
      if (stockCountId) this.created.stockCounts.push(stockCountId);
      const items = listFrom({ data: stockCount?.items || stockCount?.details || [] })
        .slice(0, 5)
        .map((item) => ({
          partCode: item.partCode || item.code,
          systemQty: Number(item.systemQty || item.qty || 0),
          countedQty: Number(item.systemQty || item.qty || 0),
        }));
      const saved = stockCountId && items.length
        ? await this.api('pos', 'PUT', `/stock-counts/${stockCountId}/items`, this.tokens.pos, { items }, { allowFailure: true })
        : { status: 0 };
      const submitted = stockCountId
        ? await this.api('pos', 'PUT', `/stock-counts/${stockCountId}/submit`, this.tokens.pos, undefined, { allowFailure: true })
        : { status: 0 };
      return { data: { stockCountId, created: created.status, saved: saved.status, submitted: submitted.status } };
    });

    let dailyCloseId = null;
    await this.step({ actor: 'pos', flow: 'day_end', action: 'daily_close_summary_create' }, async () => {
      const summary = await this.api('pos', 'GET', `/daily-closes/summary?branchId=${config.pos.branchId}&posId=${config.pos.posId}`, this.tokens.pos, undefined, { allowFailure: true });
      const created = await this.api('pos', 'POST', '/daily-closes', this.tokens.pos, {
        branchId: config.pos.branchId,
        posId: config.pos.posId,
        notes: `${config.tag} daily close`,
        specialNote: config.tag,
      }, { allowFailure: true });
      const close = unwrap(created.json);
      dailyCloseId = close?.id || close?.dailyCloseId;
      if (dailyCloseId) this.created.dailyCloses.push(dailyCloseId);
      return { data: { summary: summary.status, created: created.status, dailyCloseId } };
    });

    await this.step({ actor: 'hqmanager', flow: 'day_end', action: 'cash_reconciliation' }, async () => {
      if (!dailyCloseId) {
        const closes = await this.api('hqmanager', 'GET', `/daily-closes?branchId=${config.pos.branchId}&limit=20&offset=0`, this.tokens.hqmanager, undefined, { allowFailure: true });
        dailyCloseId = listFrom(closes.json).find((c) => c.status === 'pending_reconciliation')?.id;
      }
      if (!dailyCloseId) return { data: { skipped: true, reason: 'no pending daily close' } };
      const recon = await this.api('hqmanager', 'POST', '/cash-reconciliations', this.tokens.hqmanager, {
        dailyCloseId,
        actualAmount: 0,
        notes: `${config.tag} cash recon`,
      }, { allowFailure: true });
      return { data: { dailyCloseId, reconciliation: recon.status } };
    });

    await this.step({ actor: 'hqmanager', flow: 'day_end', action: 'variance_report' }, async () => {
      if (!stockCountId) return { data: { skipped: true, reason: 'no stock count id' } };
      const report = await this.api('hqmanager', 'GET', `/reports/stock-variance?countId=${encodeURIComponent(stockCountId)}`, this.tokens.hqmanager, undefined, { allowFailure: true });
      return { data: { stockCountId, report: report.status } };
    });

    await this.step({ actor: 'admin', flow: 'support', action: 'support_pos_monitor_list' }, async () => {
      const page = await this.page('admin-ui');
      await page.goto(config.webUrl, { waitUntil: 'domcontentloaded', timeout: config.timeoutMs });
      const res = await this.api('admin', 'POST', '/pos-mirror/test-state', this.tokens.admin, {
        lastAction: config.tag,
      }, { allowFailure: true });
      const shot = await this.screenshot('admin-ui', 'support-monitor-page');
      return { screenshots: [shot], data: { status: res.status } };
    });

    await this.step({ actor: 'pos', flow: 'security', action: 'rbac_forbidden_users_api', allowedStatuses: [403] }, async () => {
      const res = await this.api('pos', 'GET', '/users', this.tokens.pos, undefined, { allowFailure: true });
      return { data: { status: res.status, expected: 403 } };
    });

    await this.writeReports();
  }

  summarize() {
    const nonPreflightRequests = this.requests.filter((r) => r.method !== 'OPTIONS');
    const slowest = [...nonPreflightRequests]
      .filter((r) => r.durationMs != null)
      .sort((a, b) => b.durationMs - a.durationMs)
      .slice(0, 15)
      .map((r) => ({
        actor: r.actor,
        method: r.method,
        path: r.path,
        status: r.status,
        durationMs: ms(r.durationMs),
      }));
    return {
      reportId: this.reportId,
      tag: config.tag,
      startedAt: this.startedAt,
      finishedAt: iso(),
      webUrl: config.webUrl,
      apiUrl: config.apiUrl,
      stepCount: this.steps.length,
      passCount: this.steps.filter((s) => s.status === 'pass').length,
      slowCount: this.steps.filter((s) => s.status === 'slow').length,
      failCount: this.steps.filter((s) => s.status === 'fail').length,
      requestCount: this.requests.length,
      preflightCount: this.requests.filter((r) => r.method === 'OPTIONS').length,
      slowest,
      created: this.created,
    };
  }

  async writeReports() {
    const summary = this.summarize();
    const jsonPath = path.join(reportRoot, `${this.reportId}.json`);
    const mdPath = path.join(reportRoot, `${this.reportId}.md`);
    const payload = {
      summary,
      steps: this.steps,
      requests: this.requests.map((r) => ({ ...r, startedAtEpochMs: undefined })),
      config: {
        webUrl: config.webUrl,
        apiUrl: config.apiUrl,
        tag: config.tag,
        sla: endpointSlaMs,
      },
    };
    fs.writeFileSync(jsonPath, JSON.stringify(payload, null, 2));
    fs.writeFileSync(mdPath, this.renderMarkdown(summary));
    console.log(`\nReport written:\n- ${path.relative(repoRoot, mdPath)}\n- ${path.relative(repoRoot, jsonPath)}`);
  }

  renderMarkdown(summary) {
    const lines = [];
    lines.push(`# POS Full-Day Production Performance Report`);
    lines.push('');
    lines.push(`- Tag: \`${summary.tag}\``);
    lines.push(`- Web: ${summary.webUrl}`);
    lines.push(`- API: ${summary.apiUrl}`);
    lines.push(`- Started: ${summary.startedAt}`);
    lines.push(`- Finished: ${summary.finishedAt}`);
    lines.push(`- Steps: ${summary.stepCount} total, ${summary.passCount} pass, ${summary.slowCount} slow, ${summary.failCount} fail`);
    lines.push(`- Requests: ${summary.requestCount} total, ${summary.preflightCount} preflight`);
    lines.push('');
    lines.push(`## Step Results`);
    lines.push('');
    lines.push('| Status | Actor | Flow | Action | Duration | First Req | Req | Preflight | Notes |');
    lines.push('|---|---|---|---:|---:|---:|---:|---:|---|');
    for (const s of this.steps) {
      lines.push(
        `| ${s.status} | ${s.actor} | ${s.flow} | ${s.action} | ${s.durationMs}ms | ${s.firstRequestMs ?? ''} | ${s.requestCount} | ${s.preflightCount} | ${s.bottleneckNotes.join('<br>')} |`,
      );
    }
    lines.push('');
    lines.push(`## Slowest Requests`);
    lines.push('');
    lines.push('| Actor | Method | Endpoint | Status | Duration |');
    lines.push('|---|---|---|---:|---:|');
    for (const r of summary.slowest) {
      lines.push(`| ${r.actor} | ${r.method} | \`${r.path}\` | ${r.status ?? ''} | ${r.durationMs}ms |`);
    }
    lines.push('');
    lines.push(`## Created Evidence Data`);
    lines.push('');
    lines.push('```json');
    lines.push(JSON.stringify(summary.created, null, 2));
    lines.push('```');
    lines.push('');
    lines.push(`## Optimization Backlog`);
    lines.push('');
    lines.push(...this.optimizationBacklog().map((item, index) => `${index + 1}. ${item}`));
    lines.push('');
    return lines.join('\n');
  }

  optimizationBacklog() {
    const notes = this.steps.flatMap((s) => s.bottleneckNotes.map((n) => ({ step: s, note: n })));
    const backlog = [];
    if (notes.some((n) => n.note.includes('scan mutation'))) {
      backlog.push('Backend/API: `add-item-by-barcode` is still above the 1s scan SLA; inspect handler timing logs, DB round trips, and Supabase latency.');
    }
    if (notes.some((n) => n.note.includes('CORS preflight'))) {
      backlog.push('API/Infra: reduce preflight cost by simplifying headers/methods where possible, increasing preflight cache age, or colocating frontend/backend behind one origin.');
    }
    if (notes.some((n) => /parts\/search|HTTP 502/.test(n.note))) {
      backlog.push('Backend/DB: optimize `/parts/search` and protect it from Render timeout/502; add indexes or bounded search strategy.');
    }
    if (notes.some((n) => n.note.includes('Frontend scan request regression'))) {
      backlog.push('Frontend: scanner input still emits multiple API calls; ensure only Enter/SCAN triggers barcode add.');
    }
    if (this.steps.some((s) => s.action === 'scanner_burst_10_barcodes' && s.durationMs > 10000)) {
      backlog.push('Product/API: add a batch barcode endpoint or optimistic cart queue for 10-item scanner bursts.');
    }
    if (!backlog.length) backlog.push('No critical bottleneck detected by current rules; compare raw JSON against future runs.');
    return backlog;
  }
}

const harness = new PerfHarness();
try {
  await harness.run();
} catch (error) {
  console.error(error);
  try {
    await harness.writeReports();
  } catch (reportError) {
    console.error('failed to write report after run error', reportError);
  }
  process.exitCode = 1;
} finally {
  await harness.close();
}
