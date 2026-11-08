const prisma = require('../config/db');
const { forbidden, notFound } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');

const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

const parseMinutes = (value, fallback = null) => {
  if (value === null || value === undefined || value === '') return fallback;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const match = String(value).match(/^(\d{1,2}):(\d{2})/);
  if (!match) return fallback;
  return Number(match[1]) * 60 + Number(match[2]);
};

const minutesToTime = (minutes) => {
  const normalized = Number(minutes);
  if (!Number.isFinite(normalized)) return '';
  const hour = Math.floor(normalized / 60).toString().padStart(2, '0');
  const minute = Math.floor(normalized % 60).toString().padStart(2, '0');
  return `${hour}:${minute}`;
};

const parseDay = (value) => {
  if (typeof value === 'number' && value >= 1 && value <= 7) return value;
  const text = String(value || '').trim();
  const numeric = Number(text);
  if (Number.isInteger(numeric) && numeric >= 1 && numeric <= 7) return numeric;
  const index = DAY_NAMES.findIndex(
    (name) => name.toLowerCase() === text.toLowerCase()
  );
  return index >= 0 ? index + 1 : null;
};

const formatSlot = (slot) => ({
  id: slot.id,
  academy_id: slot.academyId,
  is_break: slot.isBreak,
  class_id: slot.classId || '',
  class_name: slot.class?.className || '',
  section: slot.section || '',
  subject: slot.subject || '',
  teacher_id: slot.teacherId || '',
  teacher_name: slot.teacher?.fullName || '',
  day_of_week: slot.dayOfWeekInt || parseDay(slot.dayOfWeek) || 1,
  start_minutes: slot.startMinutes ?? parseMinutes(slot.startTime, 0),
  end_minutes: slot.endMinutes ?? parseMinutes(slot.endTime, 0),
  room: slot.room || '',
  semester: slot.semester || '',
  effective_from: toIso(slot.effectiveFrom),
  effective_to: toIso(slot.effectiveTo),
  created_at: toIso(slot.createdAt),
  updated_at: toIso(slot.updatedAt || slot.createdAt)
});

const slotInclude = {
  teacher: { select: { fullName: true } },
  class: { select: { className: true, section: true } }
};

const classIdsForUser = async (req) => {
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

const getTimetable = async (req, res, next) => {
  try {
    const whereClause = { academyId: req.academyId };
    const requestedClassIds = req.query.classIds
      ? String(req.query.classIds).split(',').map((value) => value.trim()).filter(Boolean)
      : req.query.classId
        ? [String(req.query.classId)]
        : null;

    if (req.user.role === 'TEACHER') {
      if (req.query.teacherId && req.query.teacherId !== req.user.id) {
        throw forbidden('Teachers can only view their own timetable.');
      }
      whereClause.teacherId = req.user.id;
    } else if (req.user.role === 'STUDENT' || req.user.role === 'PARENT') {
      const allowed = await classIdsForUser(req);
      const requested = requestedClassIds || allowed;
      const scoped = requested.filter((classId) => allowed.includes(classId));
      whereClause.classId = { in: scoped };
    } else {
      if (requestedClassIds) whereClause.classId = { in: requestedClassIds };
      if (req.query.teacherId) whereClause.teacherId = String(req.query.teacherId);
    }

    if (req.query.semester) whereClause.semester = String(req.query.semester);
    if (req.query.dayOfWeek) {
      const day = parseDay(req.query.dayOfWeek);
      if (!day) {
        return res.status(400).json({ success: false, message: 'Invalid dayOfWeek.' });
      }
      whereClause.OR = [{ dayOfWeekInt: day }, { dayOfWeek: String(day) }];
    }

    const slots = await prisma.timetableSlot.findMany({
      where: whereClause,
      include: slotInclude,
      orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }]
    });
    return sendSuccess(res, slots.map(formatSlot));
  } catch (err) {
    next(err);
  }
};

const normaliseSlotInput = async (req, existing = null) => {
  const body = req.body;
  const isBreak = body.isBreak === true || body.is_break === true;
  const rawClassId = body.classId ?? body.class_id ?? existing?.classId;
  const rawTeacherId = body.teacherId ?? body.teacher_id ?? existing?.teacherId;
  const day = parseDay(body.dayOfWeek ?? body.day_of_week ?? existing?.dayOfWeekInt ?? existing?.dayOfWeek);
  const startMinutes = parseMinutes(
    body.startMinutes ?? body.start_minutes ?? body.startTime ?? body.start_time,
    existing?.startMinutes ?? parseMinutes(existing?.startTime)
  );
  const endMinutes = parseMinutes(
    body.endMinutes ?? body.end_minutes ?? body.endTime ?? body.end_time,
    existing?.endMinutes ?? parseMinutes(existing?.endTime)
  );

  if (!day) throw new Error('dayOfWeek must be a weekday number (1-7).');
  if (startMinutes == null || endMinutes == null || endMinutes <= startMinutes) {
    throw new Error('start and end times are required and end must follow start.');
  }

  let classEntity = null;
  if (rawClassId) {
    classEntity = await prisma.class.findFirst({
      where: { id: String(rawClassId), academyId: req.academyId }
    });
    if (!classEntity) throw forbidden('The selected class does not belong to this academy.');
  } else if (!isBreak) {
    throw new Error('classId is required for non-break timetable slots.');
  }

  if (rawTeacherId) {
    const teacher = await prisma.user.findFirst({
      where: {
        id: String(rawTeacherId),
        academyId: req.academyId,
        role: 'TEACHER'
      }
    });
    if (!teacher) throw forbidden('The selected teacher does not belong to this academy.');
  } else if (!isBreak && classEntity?.primaryTeacherId) {
    // A scheduled lesson without an explicit teacher falls back to the
    // subject offering's primary teacher.
  }

  const subject = String(body.subject ?? existing?.subject ?? '').trim();
  if (!isBreak && !subject) throw new Error('subject is required for lessons.');

  return {
    academyId: req.academyId,
    classId: classEntity ? classEntity.id : null,
    section: String(body.section ?? existing?.section ?? classEntity?.section ?? ''),
    dayOfWeek: String(day),
    dayOfWeekInt: day,
    startTime: minutesToTime(startMinutes),
    endTime: minutesToTime(endMinutes),
    startMinutes,
    endMinutes,
    subject,
    teacherId: rawTeacherId ? String(rawTeacherId) : classEntity?.primaryTeacherId || null,
    room: body.room !== undefined ? String(body.room || '') : existing?.room || '',
    semester: body.semester !== undefined
      ? String(body.semester || '')
      : existing?.semester || '',
    isBreak,
    effectiveFrom: body.effectiveFrom || body.effective_from
      ? new Date(body.effectiveFrom ?? body.effective_from)
      : existing?.effectiveFrom || null,
    effectiveTo: body.effectiveTo || body.effective_to
      ? new Date(body.effectiveTo ?? body.effective_to)
      : existing?.effectiveTo || null
  };
};

const findCollision = async (data, excludeId = null) => {
  if (data.isBreak) return null;
  const slots = await prisma.timetableSlot.findMany({
    where: {
      academyId: data.academyId,
      dayOfWeekInt: data.dayOfWeekInt,
      isBreak: false,
      ...(excludeId ? { id: { not: excludeId } } : {}),
      OR: [
        ...(data.teacherId ? [{ teacherId: data.teacherId }] : []),
        ...(data.classId ? [{ classId: data.classId }] : [])
      ]
    }
  });
  return slots.find((slot) => {
    const start = slot.startMinutes ?? parseMinutes(slot.startTime, 0);
    const end = slot.endMinutes ?? parseMinutes(slot.endTime, 0);
    return data.startMinutes < end && data.endMinutes > start;
  });
};

const createTimetableSlot = async (req, res, next) => {
  try {
    let data;
    try {
      data = await normaliseSlotInput(req);
    } catch (error) {
      return res.status(400).json({ success: false, message: error.message });
    }

    const collision = await findCollision(data);
    if (collision) {
      return res.status(409).json({
        success: false,
        message: 'The teacher or class is already scheduled during this time.'
      });
    }

    const slot = await prisma.timetableSlot.create({
      data,
      include: slotInclude
    });
    return sendSuccess(res, formatSlot(slot), {
      status: 201,
      message: 'Timetable slot created.'
    });
  } catch (err) {
    next(err);
  }
};

const updateTimetableSlot = async (req, res, next) => {
  try {
    const existing = await prisma.timetableSlot.findFirst({
      where: { id: req.params.id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Timetable slot not found in academy.');

    let data;
    try {
      data = await normaliseSlotInput(req, existing);
    } catch (error) {
      return res.status(400).json({ success: false, message: error.message });
    }

    const collision = await findCollision(data, existing.id);
    if (collision) {
      return res.status(409).json({
        success: false,
        message: 'The teacher or class is already scheduled during this time.'
      });
    }

    const slot = await prisma.timetableSlot.update({
      where: { id: existing.id },
      data,
      include: slotInclude
    });
    return sendSuccess(res, formatSlot(slot), {
      message: 'Timetable slot updated.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteTimetableSlot = async (req, res, next) => {
  try {
    const existing = await prisma.timetableSlot.findFirst({
      where: { id: req.params.id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Timetable slot not found in academy.');
    await prisma.timetableSlot.delete({ where: { id: existing.id } });
    return sendSuccess(res, { deleted: true }, { message: 'Slot removed.' });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getTimetable,
  createTimetableSlot,
  updateTimetableSlot,
  deleteTimetableSlot
};
