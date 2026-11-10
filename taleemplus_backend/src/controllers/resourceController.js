const prisma = require('../config/db');
const { toIso } = require('../utils/dto');
const { notFound, forbidden } = require('../utils/apiError');
const { canManageClass } = require('../services/fileAccess');
const { deleteFilesForOwner, toDto: fileDto } = require('./fileController');
const { sendSuccess } = require('../utils/response');
const {
  assertClassInAcademy,
  assertEnrolledStudent
} = require('../utils/tenant');

const formatResource = (resource) => ({
  id: resource.id,
  academy_id: resource.academyId,
  class_id: resource.classId,
  teacher_id: resource.teacherId,
  teacher_name: resource.teacher?.fullName || '',
  title: resource.title,
  description: resource.description || '',
  file_url: resource.fileUrl,
  content_text: resource.contentText || '',
  file_name: resource.fileName || '',
  mime_type: resource.mimeType || '',
  created_at: toIso(resource.createdAt),
  updated_at: toIso(resource.updatedAt)
});

const visibleClassIds = async (req) => {
  if (req.user.role === 'STUDENT') {
    const rows = await prisma.studentEnrollment.findMany({
      where: { studentId: req.user.id },
      select: { classId: true }
    });
    return rows.map((row) => row.classId);
  }
  if (req.user.role === 'PARENT') {
    const links = await prisma.parentStudent.findMany({
      where: { parentId: req.user.id },
      select: { studentId: true }
    });
    const rows = await prisma.studentEnrollment.findMany({
      where: { studentId: { in: links.map((link) => link.studentId) } },
      select: { classId: true }
    });
    return [...new Set(rows.map((row) => row.classId))];
  }
  return null;
};

const formatQuery = (query) => ({
  id: query.id,
  academy_id: query.academyId,
  class_id: query.classId,
  student_id: query.studentId,
  student_name: query.student?.fullName || '',
  teacher_id: query.teacherId,
  teacher_name: query.teacher?.fullName || '',
  question: query.question,
  answer: query.answer || '',
  is_resolved: query.isResolved,
  created_at: toIso(query.createdAt),
  answered_at: toIso(query.answeredAt)
});

const getResources = async (req, res, next) => {
  try {
    const { classId } = req.query;
    const whereClause = { academyId: req.academyId };
    if (classId) {
      await assertClassInAcademy(classId, req.academyId);
      const scoped = await visibleClassIds(req);
      if (scoped && !scoped.includes(classId)) {
        throw forbidden('You cannot view materials for this class.');
      }
      whereClause.classId = classId;
    } else {
      const scoped = await visibleClassIds(req);
      if (scoped) whereClause.classId = { in: scoped };
    }
    if (req.query.teacherId) whereClause.teacherId = String(req.query.teacherId);

    const resources = await prisma.sharedResource.findMany({
      where: whereClause,
      include: { teacher: { select: { fullName: true } } },
      orderBy: { createdAt: 'desc' },
      take: 500
    });

    // Attach uploaded files (metadata only; bytes are fetched through the
    // authorised /files/:id/content route).
    const files = resources.length
      ? await prisma.storedFile.findMany({
          where: {
            academyId: req.academyId,
            category: 'COURSE_MATERIAL',
            ownerId: { in: resources.map((r) => r.id) }
          },
          orderBy: { createdAt: 'asc'}
        })
      : [];
    return sendSuccess(res, resources.map((r) => ({
      ...formatResource(r),
      files: files.filter((f) => f.ownerId === r.id).map(fileDto)
    })));
  } catch (err) {
    next(err);
  }
};

const createResource = async (req, res, next) => {
  try {
    const { classId, title, description, fileUrl, contentText, fileName, mimeType } = req.body;
    const cls = await assertClassInAcademy(classId, req.academyId);
    if (!canManageClass(req, cls)) {
      throw forbidden('You can only share materials with classes you teach.');
    }

    const resource = await prisma.sharedResource.create({
      data: {
        academyId: req.academyId,
        classId,
        teacherId: req.user.id,
        title: String(title).trim(),
        description: description || null,
        fileUrl: fileUrl || null,
        contentText: contentText || null,
        fileName: fileName || null,
        mimeType: mimeType || null
      },
      include: { teacher: { select: { fullName: true } } }
    });

    return sendSuccess(res, formatResource(resource), {
      status: 201,
      message: 'Resource published successfully.'
    });
  } catch (err) {
    next(err);
  }
};

/** Admin, the uploading teacher, or the class's teacher may change it. */
const loadManagedResource = async (req) => {
  const existing = await prisma.sharedResource.findFirst({
    where: { id: req.params.id, academyId: req.academyId },
    include: { class: true }
  });
  if (!existing) throw notFound('Resource not found in this academy.');
  const owner = req.user.role === 'TEACHER' && existing.teacherId === req.user.id;
  if (!owner && !canManageClass(req, existing.class)) {
    throw forbidden('You can only change materials you shared or for classes you teach.');
  }
  return existing;
};

const updateResource = async (req, res, next) => {
  try {
    const existing = await loadManagedResource(req);
    const data = {};
    for (const field of ['title', 'description', 'fileUrl', 'contentText', 'fileName', 'mimeType']) {
      if (req.body[field] !== undefined) {
        data[field] = req.body[field] === null ? null : String(req.body[field]);
      }
    }
    if (!Object.keys(data).length) {
      return res.status(400).json({ success: false, message: 'No resource fields provided.' });
    }
    const updated = await prisma.sharedResource.update({
      where: { id: existing.id },
      data,
      include: { teacher: { select: { fullName: true } } }
    });
    return sendSuccess(res, formatResource(updated), {
      message: 'Resource updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteResource = async (req, res, next) => {
  try {
    const existing = await loadManagedResource(req);
    await deleteFilesForOwner(req.academyId, 'COURSE_MATERIAL', existing.id);
    await prisma.sharedResource.delete({ where: { id: existing.id } });
    return sendSuccess(res, { deleted: true }, {
      message: 'Resource deleted successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const getQueries = async (req, res, next) => {
  try {
    const { classId } = req.query;
    const whereClause = { academyId: req.academyId };
    if (classId) {
      await assertClassInAcademy(classId, req.academyId);
      whereClause.classId = classId;
    }
    if (req.user.role === 'STUDENT') {
      whereClause.studentId = req.user.id;
    } else if (req.user.role === 'PARENT') {
      const links = await prisma.parentStudent.findMany({
        where: { parentId: req.user.id },
        select: { studentId: true }
      });
      whereClause.studentId = { in: links.map((link) => link.studentId) };
    } else if (req.query.teacherId) {
      whereClause.teacherId = String(req.query.teacherId);
    }

    const queries = await prisma.studentQuery.findMany({
      where: whereClause,
      include: {
        student: { select: { fullName: true } },
        teacher: { select: { fullName: true } }
      },
      orderBy: { createdAt: 'desc' }
    });

    return sendSuccess(res, queries.map(formatQuery));
  } catch (err) {
    next(err);
  }
};

const createQuery = async (req, res, next) => {
  try {
    const { classId, question } = req.body;
    await assertClassInAcademy(classId, req.academyId);
    await assertEnrolledStudent(classId, req.user.id, req.academyId);

    const query = await prisma.studentQuery.create({
      data: {
        academyId: req.academyId,
        classId,
        studentId: req.user.id,
        question
      },
      include: {
        student: { select: { fullName: true } },
        teacher: { select: { fullName: true } }
      }
    });

    return sendSuccess(res, formatQuery(query), {
      status: 201,
      message: 'Query submitted successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const answerQuery = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { answer } = req.body;

    const existing = await prisma.studentQuery.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Query not found in this academy.');

    const updated = await prisma.studentQuery.update({
      where: { id: existing.id },
      data: {
        teacherId: req.user.id,
        answer,
        isResolved: true,
        answeredAt: new Date()
      },
      include: {
        student: { select: { fullName: true } },
        teacher: { select: { fullName: true } }
      }
    });

    return sendSuccess(res, formatQuery(updated), {
      message: 'Query answered successfully.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getResources,
  createResource,
  updateResource,
  deleteResource,
  getQueries,
  createQuery,
  answerQuery
};
