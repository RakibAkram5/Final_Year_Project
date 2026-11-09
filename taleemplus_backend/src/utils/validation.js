const { z } = require('zod');
const { sendError } = require('./response');
const { ERROR_CODES } = require('./apiError');

const DATE_ONLY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

const isValidDateOnly = (value) => {
  if (!DATE_ONLY_PATTERN.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
};

const uuid = z.string().uuid('Must be a valid UUID.');
const dateOnly = z
  .string()
  .refine(isValidDateOnly, 'Must be a valid calendar date in YYYY-MM-DD format.');
const isoDateTime = z
  .string()
  .datetime({ offset: true, message: 'Must be an ISO-8601 date-time.' });
const role = z.enum(['ADMIN', 'TEACHER', 'STUDENT', 'PARENT']);
const attendanceStatus = z.enum(['present', 'absent', 'late', 'leave']);

const pagination = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20)
});

const classIdQuery = z.object({
  classId: uuid.optional()
});

const attendanceClassQuery = z.object({
  classId: uuid,
  logDate: dateOnly
});

const attendanceMarkBody = z.object({
  classId: uuid,
  logDate: dateOnly,
  records: z
    .array(
      z.object({
        studentId: uuid,
        status: attendanceStatus.default('present')
      })
    )
    .min(1, 'At least one attendance record is required.')
    .max(500, 'A maximum of 500 attendance records can be saved at once.')
    .refine(
      (records) =>
        new Set(records.map((record) => record.studentId)).size === records.length,
      'Each student may only appear once per attendance request.'
    )
});

const loginBody = z.object({
  email: z.string().trim().email('A valid email address is required.'),
  password: z.string().min(1, 'Password is required.')
});

const registerAdminBody = z.object({
  email: z.string().trim().email('A valid email address is required.'),
  password: z.string().min(1, 'Password is required.'),
  fullName: z.string().trim().min(1, 'Full name is required.').max(120),
  academyName: z.string().trim().min(1, 'Academy name is required.').max(120),
  academyAddress: z.string().trim().max(240).optional(),
  academyPhone: z.string().trim().max(40).optional()
});

const registerUserBody = z.object({
  email: z.string().trim().email('A valid email address is required.'),
  password: z.string().min(1, 'Password is required.'),
  fullName: z.string().trim().min(1, 'Full name is required.').max(120),
  role: z.enum(['admin', 'teacher', 'student', 'parent'], {
    message: 'Role must be admin, teacher, student, or parent.'
  }),
  academyCode: z.string().trim().min(1, 'Academy code is required.'),
  phoneNumber: z.string().trim().max(40).optional(),
  securityQuestion: z.string().trim().max(200).optional(),
  securityAnswer: z.string().trim().max(200).optional()
});

const securityQuestionQuery = z.object({
  email: z.string().trim().email('A valid email address is required.')
});

const resetPasswordBody = z.object({
  email: z.string().trim().email('A valid email address is required.'),
  securityAnswer: z.string().trim().min(1, 'Security answer is required.').max(200),
  newPassword: z.string().min(1, 'New password is required.')
});

const createResourceBody = z
  .object({
    classId: uuid,
    title: z.string().trim().min(1, 'Title is required.').max(200),
    description: z.string().trim().max(2000).optional(),
    fileUrl: z.string().trim().max(2000).optional(),
    contentText: z.string().trim().max(50000).optional(),
    fileName: z.string().trim().max(300).optional(),
    mimeType: z.string().trim().max(120).optional(),
    // The client uploads the file to /files right after creating the record.
    withAttachment: z.boolean().optional()
  })
  .refine((value) => Boolean(value.fileUrl || value.contentText || value.withAttachment), {
    message: 'Add a file, a link or text content.',
    path: ['fileUrl']
  });

const createQueryBody = z.object({
  classId: uuid,
  question: z.string().trim().min(1, 'Question is required.').max(5000)
});

const answerQueryBody = z.object({
  answer: z.string().trim().min(1, 'Answer text is required.').max(5000)
});

const idParam = z.object({ id: uuid });
const studentIdParam = z.object({ studentId: uuid });

const validate = (schema, source = 'body') => (req, res, next) => {
  const result = schema.safeParse(req[source] || {});
  if (!result.success) {
    const details = result.error.issues.map((issue) => ({
      path: issue.path.join('.'),
      message: issue.message,
      code: issue.code
    }));
    return sendError(
      res,
      400,
      ERROR_CODES.VALIDATION_ERROR,
      'Request validation failed.',
      details
    );
  }
  req[source] = result.data;
  next();
};

module.exports = {
  z,
  uuid,
  dateOnly,
  isoDateTime,
  role,
  attendanceStatus,
  pagination,
  classIdQuery,
  attendanceClassQuery,
  attendanceMarkBody,
  loginBody,
  registerAdminBody,
  registerUserBody,
  securityQuestionQuery,
  resetPasswordBody,
  createResourceBody,
  createQueryBody,
  answerQueryBody,
  idParam,
  studentIdParam,
  isValidDateOnly,
  validate
};
