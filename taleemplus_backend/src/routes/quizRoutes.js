const express = require('express');
const router = express.Router();
const quizController = require('../controllers/quizController');
const { authenticateToken } = require('../middleware/authMiddleware');
const { authorizeRoles } = require('../middleware/roleMiddleware');

router.use(authenticateToken);

router.get('/', quizController.getQuizzes);
router.get(
  '/marks/academy',
  authorizeRoles('ADMIN', 'TEACHER'),
  quizController.getAllAcademyMarks
);
router.get(
  '/marks/quiz/:quizId',
  authorizeRoles('ADMIN', 'TEACHER'),
  quizController.getMarksByQuiz
);
router.get(
  '/marks/class/:classId',
  authorizeRoles('ADMIN', 'TEACHER'),
  quizController.getMarksByClass
);
router.get('/marks/student/:studentId', quizController.getStudentMarks);
router.post('/marks', authorizeRoles('ADMIN', 'TEACHER'), quizController.upsertTestMark);
router.delete(
  '/marks/:id',
  authorizeRoles('ADMIN', 'TEACHER'),
  quizController.deleteMark
);
router.post(
  '/ai-generate',
  authorizeRoles('ADMIN', 'TEACHER'),
  quizController.aiGenerate
);
router.get('/:id', quizController.getQuizById);
router.post('/', authorizeRoles('ADMIN', 'TEACHER'), quizController.createQuiz);
router.put('/:id', authorizeRoles('ADMIN', 'TEACHER'), quizController.updateQuiz);
router.put(
  '/:id/questions',
  authorizeRoles('ADMIN', 'TEACHER'),
  quizController.updateQuizQuestions
);
router.delete('/:id', authorizeRoles('ADMIN', 'TEACHER'), quizController.deleteQuiz);

module.exports = router;
