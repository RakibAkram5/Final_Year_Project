const ai = require('../src/services/aiQuestionService');

describe('aiQuestionService', () => {
  const saved = {};
  beforeEach(() => {
    saved.a = process.env.AI_API_KEY;
    saved.b = process.env.AI_GATEWAY_API_KEY;
    delete process.env.AI_API_KEY;
    delete process.env.AI_GATEWAY_API_KEY;
  });
  afterEach(() => {
    if (saved.a === undefined) delete process.env.AI_API_KEY;
    else process.env.AI_API_KEY = saved.a;
    if (saved.b === undefined) delete process.env.AI_GATEWAY_API_KEY;
    else process.env.AI_GATEWAY_API_KEY = saved.b;
  });

  it('is disabled when no AI key is configured', () => {
    expect(ai.isConfigured()).toBe(false);
  });

  it('is enabled once a key is present', () => {
    process.env.AI_API_KEY = 'sk-test-key';
    expect(ai.isConfigured()).toBe(true);
  });

  it('keeps only well-formed questions', () => {
    const items = ai.sanitizeItems([
      {
        type: 'mcq',
        text: 'Base of binary?',
        options: ['2', '8', '10', '16'],
        correctIndex: 0,
        answer: '2'
      },
      { type: 'mcq', text: 'too few options', options: ['a', 'b'] },
      { type: 'short', text: 'Define RAM', answer: 'Random Access Memory' },
      { type: 'short', text: '' }, // no text -> dropped
      { type: 'essay', text: 'invalid type' } // bad type -> dropped
    ]);
    expect(items).toHaveLength(2);
    expect(items[0]).toMatchObject({ type: 'mcq', correctIndex: 0 });
    expect(items[0].options).toHaveLength(4);
    expect(items[1]).toMatchObject({ type: 'short' });
  });

  it('clamps an out-of-range correctIndex to 0', () => {
    const [item] = ai.sanitizeItems([
      {
        type: 'mcq',
        text: 'q',
        options: ['a', 'b', 'c', 'd'],
        correctIndex: 9
      }
    ]);
    expect(item.correctIndex).toBe(0);
  });

  it('parses JSON content wrapped in a code fence', () => {
    const content =
      '```json\n{"items":[{"type":"short","text":"Define bit","answer":"0 or 1"}]}\n```';
    const items = ai.parseContent(content);
    expect(items).toHaveLength(1);
    expect(items[0].text).toBe('Define bit');
  });

  it('returns an empty list for unparseable content', () => {
    expect(ai.parseContent('sorry, I cannot do that')).toEqual([]);
  });
});
