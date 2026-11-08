const express = require('express');
const router = express.Router();
const classSectionController = require('../controllers/classSectionController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/', classSectionController.getSections);
router.post('/', authorizeRoles('ADMIN'), classSectionController.createSection);
router.put('/:id', authorizeRoles('ADMIN'), classSectionController.updateSection);
router.delete('/:id', authorizeRoles('ADMIN'), classSectionController.deleteSection);
router.put('/:id/enrollment', authorizeRoles('ADMIN'), classSectionController.updateEnrollment);
router.post('/:id/enroll', authorizeRoles('ADMIN'), classSectionController.enrollStudent);
router.delete(
  '/:id/enroll/:studentId',
  authorizeRoles('ADMIN'),
  classSectionController.unenrollStudent
);

module.exports = router;
