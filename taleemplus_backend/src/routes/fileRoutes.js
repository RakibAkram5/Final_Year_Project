const express = require('express');
const router = express.Router();
const fileController = require('../controllers/fileController');
const { authenticateToken } = require('../middleware/authMiddleware');

// Raw bytes, parsed only on the routes that accept uploads. The limit is a
// little above MAX_UPLOAD_BYTES so the controller can return a clear 413.
const rawUpload = express.raw({
  type: 'application/octet-stream',
  limit: fileController.MAX_UPLOAD_BYTES + 1024
});

router.use(authenticateToken);

router.get('/', fileController.listFiles);
router.post('/', rawUpload, fileController.uploadFile);
router.get('/:id/content', fileController.downloadFile);
router.put('/:id/content', rawUpload, fileController.replaceFile);
router.delete('/:id', fileController.deleteFile);

module.exports = router;
