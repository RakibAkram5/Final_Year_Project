/**
 * Academy white-label branding: upload / update / remove the logo, contact
 * identity, and strict tenant isolation. Runs only with TEST_DATABASE_URL.
 */
const request = require('supertest');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { createAcademyTeam } = require('./helpers/contractFixtures');
const { png } = require('./helpers/images');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, url, token) => {
  const req = request(app)[method](`/api/v2${url}`);
  return token ? req.set('Authorization', `Bearer ${token}`) : req;
};

describeWithDatabase('Academy branding (white-label)', () => {
  jest.setTimeout(90000);
  let A; let B;

  beforeAll(async () => {
    A = await createAcademyTeam('BrandA');
    B = await createAcademyTeam('BrandB');
  });
  afterAll(async () => {
    for (const t of [A, B]) await prisma.academy.delete({ where: { id: t.academy.id } }).catch(() => {});
  });

  it('starts with the academy name and no custom logo', async () => {
    const r = await api('get', '/academy/branding', A.tokens.student);
    expect(r.statusCode).toBe(200);
    expect(r.body.data).toMatchObject({ academyId: A.academy.id, name: A.academy.name, hasCustomLogo: false, logo: null });
  });

  it('admin uploads a logo and identity; every role in that academy sees it', async () => {
    const logo = png(24, 24).toString('base64');
    const r = await api('put', '/academy/branding', A.tokens.admin).send({
      name: 'Al-Noor Science Academy', address: '12 Mall Road, Lahore', phone: '+92 300 1234567',
      email: 'office@alnoor.example', logoBase64: logo, logoMimeType: 'image/png',
    });
    expect(r.statusCode).toBe(200);
    expect(r.body.data).toMatchObject({ name: 'Al-Noor Science Academy', email: 'office@alnoor.example', hasCustomLogo: true, logoMimeType: 'image/png' });
    expect(r.body.data.logo).toBe(`data:image/png;base64,${logo}`);

    for (const role of ['admin', 'teacher', 'student', 'parent']) {
      const me = await api('get', '/auth/me', A.tokens[role]);
      expect(me.body.data.academyName).toBe('Al-Noor Science Academy');
      expect(me.body.data.academyEmail).toBe('office@alnoor.example');
      expect(me.body.data.academyLogo).toBe(`data:image/png;base64,${logo}`);
      const branding = await api('get', '/academy/branding', A.tokens[role]);
      expect(branding.body.data.logo).toBe(`data:image/png;base64,${logo}`);
    }
    // Login responses carry the branding too, so it is correct right after sign-in.
    const login = await request(app).post('/api/v2/auth/login').send({ email: A.teacher.email, password: 'ContractTest!7' });
    expect(login.body.data.user.academyLogo).toBe(`data:image/png;base64,${logo}`);
  });

  it('never leaks one academy\'s identity to another', async () => {
    const other = await api('get', '/academy/branding', B.tokens.admin);
    expect(other.body.data.name).toBe(B.academy.name);
    expect(other.body.data.logo).toBeNull();
    const me = await api('get', '/auth/me', B.tokens.student);
    expect(me.body.data.academyLogo).toBeNull();
    expect(me.body.data.academyName).not.toBe('Al-Noor Science Academy');
    // B's admin cannot change A, even by naming A's id in the body.
    await api('put', '/academy/branding', B.tokens.admin).send({ academyId: A.academy.id, name: 'Hijacked' });
    const a = await api('get', '/academy/branding', A.tokens.admin);
    expect(a.body.data.name).toBe('Al-Noor Science Academy');
  });

  it('validates uploads server-side and rejects non-admins', async () => {
    const bad = [
      { logoBase64: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>').toString('base64'), logoMimeType: 'image/svg+xml' },
      { logoBase64: png(4, 4).toString('base64'), logoMimeType: 'image/jpeg' },
      { logoBase64: png(1100, 2).toString('base64'), logoMimeType: 'image/png' },
      { name: '' },
      { email: 'not-an-email' },
      { name: 'x'.repeat(121) },
      {},
    ];
    for (const body of bad) {
      const r = await api('put', '/academy/branding', A.tokens.admin).send(body);
      expect(r.statusCode).toBe(400);
    }
    for (const role of ['teacher', 'student', 'parent']) {
      expect((await api('put', '/academy/branding', A.tokens[role]).send({ name: 'Nope' })).statusCode).toBe(403);
    }
    expect((await api('get', '/academy/branding')).statusCode).toBe(401);
  });

  it('exposes only name + logo publicly by academy code (login screen)', async () => {
    const r = await api('get', `/academy/branding/public?code=${A.academy.code.toLowerCase()}`);
    expect(r.statusCode).toBe(200);
    expect(Object.keys(r.body.data).sort()).toEqual(['academyCode', 'logo', 'name']);
    expect(r.body.data.name).toBe('Al-Noor Science Academy');
    expect((await api('get', '/academy/branding/public?code=NOPE-0000')).statusCode).toBe(404);
  });

  it('removes the logo and keeps the rest of the identity', async () => {
    const r = await api('put', '/academy/branding', A.tokens.admin).send({ removeLogo: true });
    expect(r.statusCode).toBe(200);
    expect(r.body.data).toMatchObject({ hasCustomLogo: false, logo: null, name: 'Al-Noor Science Academy' });
    const me = await api('get', '/auth/me', A.tokens.parent);
    expect(me.body.data.academyLogo).toBeNull();
  });
});
