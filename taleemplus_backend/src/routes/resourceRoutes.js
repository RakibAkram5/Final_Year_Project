const express = require('express');
const router = express.Router();
const resourceController = require('../controllers/resourceController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');
const {
  validate,
  classIdQuery,
  createResourceBody,
  createQueryBody,
  answerQueryBody,
  idParam
} = require('../utils/validation');

router.get(
  '/resources',
  authenticateToken,
  validate(classIdQuery, 'query'),
  resourceController.getResources
);
router.post(
  '/resources',
  authenticateToken,
  authorizeRoles('ADMIN', 'TEACHER'),
  validate(createResourceBody),
  resourceController.createResource
);
router.put(
  '/resources/:id',
  authenticateToken,
  authorizeRoles('ADMIN', 'TEACHER'),
  validate(idParam, 'params'),
  resourceController.updateResource
);
router.delete(
  '/resources/:id',
  authenticateToken,
  authorizeRoles('ADMIN', 'TEACHER'),
  validate(idParam, 'params'),
  resourceController.deleteResource
);
router.get(
  '/queries',
  authenticateToken,
  validate(classIdQuery, 'query'),
  resourceController.getQueries
);
router.post(
  '/queries',
  authenticateToken,
  authorizeRoles('STUDENT'),
  validate(createQueryBody),
  resourceController.createQuery
);
router.put(
  '/queries/:id/answer',
  authenticateToken,
  authorizeRoles('ADMIN', 'TEACHER'),
  validate(idParam, 'params'),
  validate(answerQueryBody),
  resourceController.answerQuery
);

module.exports = router;
