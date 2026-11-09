const express = require('express');
const router = express.Router();
const geo = require('../controllers/geoController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken, authorizeRoles('ADMIN'));
router.get('/search', geo.search);
router.get('/reverse', geo.reverse);

module.exports = router;
