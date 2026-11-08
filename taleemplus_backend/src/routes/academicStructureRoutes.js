const express = require('express');
const router = express.Router();
const academicStructureController = require('../controllers/academicStructureController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/', academicStructureController.getStructure);
router.put(
  '/',
  authorizeRoles('ADMIN'),
  academicStructureController.updateStructure
);

module.exports = router;
