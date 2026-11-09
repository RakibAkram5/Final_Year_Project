const express = require('express');
const router = express.Router();
const c = require('../controllers/reportController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);
router.use(authorizeRoles('ADMIN', 'TEACHER'));

router.get('/attendance.xlsx', c.attendanceXlsx);
router.get('/results.xlsx', c.resultsXlsx);
router.get('/fees.xlsx', c.feesXlsx);

module.exports = router;
