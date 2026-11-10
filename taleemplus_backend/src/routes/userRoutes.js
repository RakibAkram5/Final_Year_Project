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
// Parents may not search the student directory: combined with self-linking
// it let a parent attach to any student. Linking is an academy-admin action.
router.get(
  '/search',
  authorizeRoles('ADMIN', 'TEACHER'),
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
router.post('/link-child', authorizeRoles('ADMIN'), userController.linkChildToParent);
router.delete(
  '/link-child/:studentId',
  authorizeRoles('ADMIN', 'PARENT'),
  userController.removeLinkedChild
);
router.post('/create', authorizeRoles('ADMIN'), userController.createUserByAdmin);

// Parent → child link requests (admin-approved). These MUST be registered
// before the "/:id" routes below, or "/link-requests" would match "/:id".
router.post('/link-requests', authorizeRoles('PARENT'), userController.createLinkRequest);
router.get('/link-requests/mine', authorizeRoles('PARENT'), userController.getMyLinkRequests);
router.get('/link-requests', authorizeRoles('ADMIN'), userController.listLinkRequests);
router.post(
  '/link-requests/:id/approve',
  authorizeRoles('ADMIN'),
  userController.approveLinkRequest
);
router.post(
  '/link-requests/:id/reject',
  authorizeRoles('ADMIN'),
  userController.rejectLinkRequest
);

router.put('/:id', authorizeRoles('ADMIN'), userController.updateUser);
router.get(
  '/:id',
  authorizeRoles('ADMIN', 'TEACHER', 'PARENT'),
  userController.getProfileById
);

module.exports = router;
