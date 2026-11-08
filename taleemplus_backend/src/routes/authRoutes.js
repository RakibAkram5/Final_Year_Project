const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');
const { authRateLimiter, refreshRateLimiter } = require('../middleware/rateLimit');
const {
  validate,
  loginBody,
  registerAdminBody,
  registerUserBody,
  securityQuestionQuery,
  resetPasswordBody
} = require('../utils/validation');

router.post('/register-admin', authRateLimiter, validate(registerAdminBody), authController.registerAdmin);
router.post('/register-user', authRateLimiter, validate(registerUserBody), authController.registerUser);
router.post('/login', authRateLimiter, validate(loginBody), authController.login);
router.post('/refresh', refreshRateLimiter, authController.refreshToken);
router.post('/logout', authController.logout);
router.get(
  '/security-question',
  authRateLimiter,
  validate(securityQuestionQuery, 'query'),
  authController.getSecurityQuestion
);
router.post(
  '/reset-password',
  authRateLimiter,
  validate(resetPasswordBody),
  authController.resetPassword
);
router.get('/academy-lookup', authRateLimiter, authController.lookupAcademy);
router.get('/me', authenticateToken, authController.getMe);
router.put('/security-question', authenticateToken, authController.setSecurityQuestion);
router.post('/verify-password', authenticateToken, authController.verifyPassword);
router.put('/password', authenticateToken, authController.changePassword);
router.put('/academy', authenticateToken, authorizeRoles('ADMIN'), authController.updateAcademyProfile);

module.exports = router;
