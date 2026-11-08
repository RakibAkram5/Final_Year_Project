const prisma = require('../config/db');
const { notFound } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');

const formatDocument = (document) => ({
  id: document.id,
  academy_id: document.academyId,
  title: document.title,
  extracted_text: document.extractedText,
  created_by_uid: document.createdById,
  created_by_name: document.createdByName || '',
  created_at: toIso(document.createdAt),
  updated_at: toIso(document.updatedAt)
});

const getDocuments = async (req, res, next) => {
  try {
    const documents = await prisma.ocrDocument.findMany({
      where: { academyId: req.academyId, createdById: req.user.id },
      orderBy: { createdAt: 'desc' },
      take: Math.min(Number(req.query.limit) || 100, 300)
    });
    return sendSuccess(res, documents.map(formatDocument));
  } catch (err) {
    next(err);
  }
};

const getDocumentById = async (req, res, next) => {
  try {
    const document = await prisma.ocrDocument.findFirst({
      where: {
        id: req.params.id,
        academyId: req.academyId,
        createdById: req.user.id
      }
    });
    if (!document) throw notFound('OCR document not found.');
    return sendSuccess(res, formatDocument(document));
  } catch (err) {
    next(err);
  }
};

const createDocument = async (req, res, next) => {
  try {
    const { title, extractedText } = req.body;
    if (!title || !extractedText) {
      return res.status(400).json({
        success: false,
        message: 'title and extractedText are required.'
      });
    }
    const document = await prisma.ocrDocument.create({
      data: {
        academyId: req.academyId,
        createdById: req.user.id,
        createdByName: req.user.fullName || req.user.email || '',
        title: String(title).trim(),
        extractedText: String(extractedText)
      }
    });
    return sendSuccess(res, formatDocument(document), {
      status: 201,
      message: 'Scanned document saved.'
    });
  } catch (err) {
    next(err);
  }
};

const updateDocument = async (req, res, next) => {
  try {
    const existing = await prisma.ocrDocument.findFirst({
      where: {
        id: req.params.id,
        academyId: req.academyId,
        createdById: req.user.id
      }
    });
    if (!existing) throw notFound('OCR document not found.');
    const data = {};
    if (req.body.title !== undefined) data.title = String(req.body.title).trim();
    if (req.body.extractedText !== undefined) {
      data.extractedText = String(req.body.extractedText);
    }
    if (!Object.keys(data).length) {
      return res.status(400).json({ success: false, message: 'No document fields provided.' });
    }
    const updated = await prisma.ocrDocument.update({
      where: { id: existing.id },
      data
    });
    return sendSuccess(res, formatDocument(updated), {
      message: 'Scanned document updated.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteDocument = async (req, res, next) => {
  try {
    const deleted = await prisma.ocrDocument.deleteMany({
      where: {
        id: req.params.id,
        academyId: req.academyId,
        createdById: req.user.id
      }
    });
    if (!deleted.count) throw notFound('OCR document not found.');
    return sendSuccess(res, { deleted: true }, {
      message: 'Scanned document deleted.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getDocuments,
  getDocumentById,
  createDocument,
  updateDocument,
  deleteDocument
};
