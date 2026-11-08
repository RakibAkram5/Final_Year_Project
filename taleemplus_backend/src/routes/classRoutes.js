const express = require('express');
const router = express.Router();
const classController = require('../controllers/classController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/', classController.getClasses);
router.post('/', authorizeRoles('ADMIN'), classController.createClass);
router.put('/:id', authorizeRoles('ADMIN'), classController.updateClass);
router.delete('/:id', authorizeRoles('ADMIN'), classController.deleteClass);
router.post('/:id/enroll', authorizeRoles('ADMIN'), classController.enrollStudent);
router.delete(
  '/:id/enroll/:studentId',
  authorizeRoles('ADMIN'),
  classController.unenrollStudent
);

module.exports = router;
