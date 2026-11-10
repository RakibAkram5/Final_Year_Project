const express = require('express');
const router = express.Router();
const c = require('../controllers/assignmentController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/', c.listAssignments);
router.post('/', authorizeRoles('ADMIN', 'TEACHER'), c.createAssignment);
router.put('/:id', authorizeRoles('ADMIN', 'TEACHER'), c.updateAssignment);
router.delete('/:id', authorizeRoles('ADMIN', 'TEACHER'), c.deleteAssignment);
router.get('/:id/submissions', authorizeRoles('ADMIN', 'TEACHER'), c.listSubmissions);
router.put(
  '/:id/submissions/:submissionId/grade',
  authorizeRoles('ADMIN', 'TEACHER'),
  c.gradeSubmission
);
router.post('/:id/submission', authorizeRoles('STUDENT'), c.submit);

module.exports = router;
