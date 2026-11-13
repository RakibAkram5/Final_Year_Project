const express = require('express');
const router = express.Router();
const controller = require('../controllers/brandingController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');
const { authRateLimiter } = require('../middleware/rateLimit');

// Unauthenticated: login-screen identity by academy code (name + logo only).
router.get('/branding/public', authRateLimiter, controller.publicBranding);

router.get('/branding', authenticateToken, controller.getBranding);
router.put('/branding', authenticateToken, authorizeRoles('ADMIN'), controller.updateBranding);

module.exports = router;
