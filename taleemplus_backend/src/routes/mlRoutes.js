const express = require('express');
const router = express.Router();
const controller = require('../controllers/mlController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken, authorizeRoles('ADMIN'));
const trainingAttempts = new Map();
const limitTraining = (req, res, next) => {
  const now = Date.now();
  const windowStart = now - 60_000;
  const recent = (trainingAttempts.get(req.user.id) || []).filter((time) => time > windowStart);
  if (recent.length >= 3) {
    return res.status(429).json({ success: false, message: 'Please wait before requesting model training again.' });
  }
  recent.push(now);
  trainingAttempts.set(req.user.id, recent);
  next();
};
router.get('/status', controller.status);
router.get('/dashboard', controller.dashboard);
router.get('/metrics', controller.metrics);
router.get('/history', controller.history);
router.post('/predict/fee-risk', limitTraining, controller.predictFee);
router.post('/predict/performance', limitTraining, controller.predictPerformance);
router.post('/train/fee-risk', limitTraining, controller.trainFee);
router.post('/train/performance', limitTraining, controller.trainPerformance);
router.post('/retrain', limitTraining, controller.retrain);
router.post('/rollback', limitTraining, controller.rollback);

module.exports = router;
