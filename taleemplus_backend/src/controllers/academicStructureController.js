const prisma = require('../config/db');
const { notFound } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');

const defaults = {
  levels: [
    { name: 'Matric', groups: ['Science', 'Arts'] },
    {
      name: 'Intermediate',
      groups: ['FSc Pre-Medical', 'FSc Pre-Engineering', 'ICS', 'ICom', 'FA']
    }
  ]
};

const getStructure = async (req, res, next) => {
  try {
    const academy = await prisma.academy.findUnique({
      where: { id: req.academyId },
      select: { academicStructure: true }
    });
    if (!academy) throw notFound('Academy not found.');
    return sendSuccess(res, academy.academicStructure || defaults);
  } catch (err) {
    next(err);
  }
};

const validateStructure = (value) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  if (!Array.isArray(value.levels)) return false;
  return value.levels.every(
    (level) =>
      level &&
      typeof level.name === 'string' &&
      level.name.trim().length > 0 &&
      level.name.length <= 80 &&
      Array.isArray(level.groups) &&
      level.groups.every(
        (group) => typeof group === 'string' && group.length <= 80
      )
  );
};

const updateStructure = async (req, res, next) => {
  try {
    if (!validateStructure(req.body)) {
      return res.status(400).json({
        success: false,
        message:
          'academic structure must contain a levels array of { name, groups[] } objects.'
      });
    }
    const academy = await prisma.academy.update({
      where: { id: req.academyId },
      data: { academicStructure: req.body },
      select: { academicStructure: true }
    });
    return sendSuccess(res, academy.academicStructure, {
      message: 'Academic structure updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = { getStructure, updateStructure, defaults };
