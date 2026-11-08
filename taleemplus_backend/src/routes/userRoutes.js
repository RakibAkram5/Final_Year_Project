const express = require('express');
const router = express.Router();
const userController = require('../controllers/userController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/pending', authorizeRoles('ADMIN'), userController.getPendingUsers);
router.put('/:id/approve', authorizeRoles('ADMIN'), userController.approveUser);
router.put('/:id/reject', authorizeRoles('ADMIN'), userController.rejectUser);
router.get(
  '/by-role',
  authorizeRoles('ADMIN', 'TEACHER', 'PARENT'),
  userController.getUsersByRole
);
router.get(
  '/directory',
  authorizeRoles('ADMIN', 'TEACHER', 'PARENT'),
  userController.getDirectory
);
router.get(
  '/search',
  authorizeRoles('ADMIN', 'TEACHER', 'PARENT'),
  userController.searchUsers
);
router.post(
  '/profiles',
  authorizeRoles('ADMIN', 'TEACHER', 'PARENT'),
  userController.getProfilesByIds
);
router.get(
  '/roll-number-available',
  authorizeRoles('ADMIN'),
  userController.checkRollNumber
);
router.put('/me', userController.updateOwnProfile);
router.put('/:id/password', authorizeRoles('ADMIN'), userController.adminResetPassword);
router.put('/:id/deactivate', authorizeRoles('ADMIN'), userController.deactivateUser);
router.put('/:id/reactivate', authorizeRoles('ADMIN'), userController.reactivateUser);
router.post('/link-child', authorizeRoles('ADMIN', 'PARENT'), userController.linkChildToParent);
router.delete(
  '/link-child/:studentId',
  authorizeRoles('ADMIN', 'PARENT'),
  userController.removeLinkedChild
);
router.post('/create', authorizeRoles('ADMIN'), userController.createUserByAdmin);
router.put('/:id', authorizeRoles('ADMIN'), userController.updateUser);
router.get(
  '/:id',
  authorizeRoles('ADMIN', 'TEACHER', 'PARENT'),
  userController.getProfileById
);

module.exports = router;
