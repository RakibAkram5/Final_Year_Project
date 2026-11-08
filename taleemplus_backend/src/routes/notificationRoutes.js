const express = require('express');
const router = express.Router();
const notificationController = require('../controllers/notificationController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/notifications', notificationController.getNotifications);
router.post(
  '/notifications',
  authorizeRoles('ADMIN'),
  notificationController.createNotification
);
router.put(
  '/notifications/read-all',
  notificationController.markAllNotificationsRead
);
router.put('/notifications/:id/read', notificationController.markNotificationRead);
router.delete('/notifications/:id', notificationController.deleteNotification);

router.get('/announcements', notificationController.getAnnouncements);
router.post(
  '/announcements',
  authorizeRoles('ADMIN', 'TEACHER'),
  notificationController.createAnnouncement
);
router.put(
  '/announcements/:id',
  authorizeRoles('ADMIN', 'TEACHER'),
  notificationController.updateAnnouncement
);
router.delete(
  '/announcements/:id',
  authorizeRoles('ADMIN', 'TEACHER'),
  notificationController.deleteAnnouncement
);

module.exports = router;
