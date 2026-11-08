const prisma = require('../taleemplus_backend/src/config/db');

module.exports = async function handler(req, res) {
  let database = 'connected';
  try {
    await prisma.$queryRaw`SELECT 1`;
  } catch (err) {
    database = 'unavailable';
    console.error('[Health] Database check failed:', err.message);
  }

  res.status(200).json({
    status: 'ok',
    service: 'TaleemPlus Backend Service',
    database,
    timestamp: new Date(),
  });
};
