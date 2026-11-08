const express = require('express');
const router = express.Router();
const ocrController = require('../controllers/ocrController');
const { authenticateToken } = require('../middleware/authMiddleware');

router.use(authenticateToken);

router.get('/', ocrController.getDocuments);
router.get('/:id', ocrController.getDocumentById);
router.post('/', ocrController.createDocument);
router.put('/:id', ocrController.updateDocument);
router.delete('/:id', ocrController.deleteDocument);

module.exports = router;
