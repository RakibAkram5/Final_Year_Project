const express = require('express');
const router = express.Router();
const attendanceController = require('../controllers/attendanceController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');
const {
  validate,
  attendanceMarkBody,
  attendanceClassQuery,
  studentIdParam
} = require('../utils/validation');

router.use(authenticateToken);

router.get('/', attendanceController.getAcademyAttendance);
router.post(
  '/mark',
  authorizeRoles('ADMIN', 'TEACHER'),
  validate(attendanceMarkBody),
  attendanceController.markAttendance
);
router.get(
  '/student/:studentId',
  validate(studentIdParam, 'params'),
  attendanceController.getStudentAttendance
);
router.get(
  '/class',
  authorizeRoles('ADMIN', 'TEACHER'),
  validate(attendanceClassQuery, 'query'),
  attendanceController.getClassAttendance
);

module.exports = router;
