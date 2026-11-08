const express = require('express');
const router = express.Router();
const classReportController = require('../controllers/classReportController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/', classReportController.getClassReports);
router.post('/', authorizeRoles('ADMIN'), classReportController.generateClassReport);
router.delete('/:id', authorizeRoles('ADMIN'), classReportController.deleteClassReport);

module.exports = router;
