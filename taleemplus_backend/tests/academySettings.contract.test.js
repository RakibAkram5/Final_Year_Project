/**
 * Academy location (Phase 6) and bank details (Phase 8).
 * The Nominatim upstream is mocked; no external requests are made.
 */
const request = require('supertest');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { createAcademyTeam } = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, url, token) =>
  request(app)[method](`/api/v2${url}`).set('Authorization', `Bearer ${token}`);

describeWithDatabase('Academy location and bank details', () => {
  jest.setTimeout(60000);
  let T; let O;

  beforeAll(async () => {
    T = await createAcademyTeam('Settings');
    O = await createAcademyTeam('SettingsOther');
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    for (const t of [T, O]) await prisma.academy.delete({ where: { id: t.academy.id } }).catch(() => {});
  });

  describe('location', () => {
    it('admin saves coordinates; every role in the academy receives them', async () => {
      const r = await api('put', '/auth/academy', T.tokens.admin).send({
        address: 'Main Boulevard, Gulberg III, Lahore',
        latitude: 31.5203696, longitude: 74.3587473, locationLabel: 'Gulberg III, Lahore'
      });
      expect(r.statusCode).toBe(200);
      expect(r.body.data.academyLatitude).toBe(31.52037);
      for (const role of ['teacher', 'student', 'parent']) {
        const me = await api('get', '/auth/me', T.tokens[role]);
        expect(me.body.data.academyLatitude).toBe(31.52037);
        expect(me.body.data.academyLongitude).toBe(74.358747);
        expect(me.body.data.academyLocationLabel).toBe('Gulberg III, Lahore');
      }
      const other = await api('get', '/auth/me', O.tokens.student);
      expect(other.body.data.academyLatitude).toBeNull();
    });

    it('validates ranges and requires admin', async () => {
      for (const bad of [{ latitude: 91, longitude: 0 }, { latitude: 10, longitude: 181 },
        { latitude: 'abc', longitude: 1 }, { latitude: 10 }]) {
        expect((await api('put', '/auth/academy', T.tokens.admin).send(bad)).statusCode).toBe(400);
      }
      expect((await api('put', '/auth/academy', T.tokens.teacher)
        .send({ latitude: 1, longitude: 1 })).statusCode).toBe(403);
    });

    it('can clear the location', async () => {
      const r = await api('put', '/auth/academy', T.tokens.admin).send({ latitude: null, longitude: null });
      expect(r.statusCode).toBe(200);
      expect(r.body.data.academyLatitude).toBeNull();
      expect(r.body.data.academyLocationLabel).toBeNull();
    });
  });

  describe('geocoder proxy', () => {
    it('searches via Nominatim with an identifying User-Agent and caches', async () => {
      const spy = jest.spyOn(global, 'fetch').mockResolvedValue({
        ok: true,
        json: async () => [{ display_name: 'Gulberg III, Lahore, Pakistan', lat: '31.5203696', lon: '74.3587473' }]
      });
      const r = await api('get', '/geo/search?q=Gulberg%20Lahore', T.tokens.admin);
      expect(r.statusCode).toBe(200);
      expect(r.body.data[0]).toEqual({ label: 'Gulberg III, Lahore, Pakistan', latitude: 31.52037, longitude: 74.358747 });
      expect(spy.mock.calls[0][1].headers['User-Agent']).toMatch(/TaleemPlus/);
      await api('get', '/geo/search?q=Gulberg%20Lahore', T.tokens.admin);
      expect(spy).toHaveBeenCalledTimes(1);
      spy.mockRestore();
    });

    it('reports the service as unavailable instead of failing hard', async () => {
      const spy = jest.spyOn(global, 'fetch').mockRejectedValue(new Error('network down'));
      const r = await api('get', '/geo/search?q=Unreachable%20place', T.tokens.admin);
      expect(r.statusCode).toBe(503);
      expect(r.body.code).toBe('GEOCODER_UNAVAILABLE');
      spy.mockRestore();
    });

    it('is admin-only and validates input', async () => {
      expect((await api('get', '/geo/search?q=Lahore', T.tokens.parent)).statusCode).toBe(403);
      expect((await api('get', '/geo/search?q=ab', T.tokens.admin)).statusCode).toBe(400);
      expect((await api('get', '/geo/reverse?lat=200&lng=1', T.tokens.admin)).statusCode).toBe(400);
    });
  });

  describe('bank details', () => {
    const base = { enabled: true, provider: 'Bank transfer', accountTitle: 'Settings Academy' };

    it('stores validated bank details, visible to the academy only', async () => {
      const r = await api('put', '/fees/payment-settings', T.tokens.admin).send({
        ...base, bankName: 'Standard Chartered', bankAccountNumber: '0011-2345-6702',
        bankIban: 'pk36 scbl 0000 0011 2345 6702', paymentInstructions: 'Write the challan number as reference.'
      });
      expect(r.statusCode).toBe(200);
      for (const role of ['parent', 'student']) {
        const g = await api('get', '/fees/payment-settings', T.tokens[role]);
        expect(g.body.data.bankIban).toBe('PK36SCBL0000001123456702');
        expect(g.body.data.bankName).toBe('Standard Chartered');
      }
      const other = await api('get', '/fees/payment-settings', O.tokens.parent);
      expect(other.body.data.bankIban).toBeNull();
    });

    it('rejects invalid IBAN/account numbers and non-admins', async () => {
      expect((await api('put', '/fees/payment-settings', T.tokens.admin)
        .send({ ...base, bankIban: 'PK36SCBL0000001123456703' })).statusCode).toBe(400);
      expect((await api('put', '/fees/payment-settings', T.tokens.admin)
        .send({ ...base, bankAccountNumber: 'abc123' })).statusCode).toBe(400);
      expect((await api('put', '/fees/payment-settings', T.tokens.parent)
        .send({ ...base })).statusCode).toBe(403);
    });

    it('refuses to enable payment instructions with no account at all', async () => {
      const r = await api('put', '/fees/payment-settings', O.tokens.admin).send({ enabled: true });
      expect(r.statusCode).toBe(400);
    });
  });
});
