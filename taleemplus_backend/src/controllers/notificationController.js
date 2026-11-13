const prisma = require('../config/db');
const { notFound, forbidden } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');

const formatNotification = (notification) => ({
  id: notification.id,
  academy_id: notification.academyId,
  recipient_id: notification.recipientId,
  title: notification.title,
  message: notification.message,
  type: notification.type,
  is_read: notification.isRead,
  created_at: toIso(notification.createdAt)
});

const getNotifications = async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const notifications = await prisma.notification.findMany({
      where: {
        academyId: req.academyId,
        recipientId: req.user.id
      },
      orderBy: { createdAt: 'desc' },
      take: limit
    });
    return sendSuccess(res, notifications.map(formatNotification));
  } catch (err) {
    next(err);
  }
};

const markNotificationRead = async (req, res, next) => {
  try {
    const updated = await prisma.notification.updateMany({
      where: { id: req.params.id, academyId: req.academyId, recipientId: req.user.id },
      data: { isRead: true }
    });
    if (!updated.count) throw notFound('Notification not found.');
    return sendSuccess(res, { read: true }, {
      message: 'Notification marked as read.'
    });
  } catch (err) {
    next(err);
  }
};

const markAllNotificationsRead = async (req, res, next) => {
  try {
    const updated = await prisma.notification.updateMany({
      where: {
        academyId: req.academyId,
        recipientId: req.user.id,
        isRead: false
      },
      data: { isRead: true }
    });
    return sendSuccess(res, { updated: updated.count }, {
      message: 'All notifications marked as read.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteNotification = async (req, res, next) => {
  try {
    const deleted = await prisma.notification.deleteMany({
      where: { id: req.params.id, academyId: req.academyId, recipientId: req.user.id }
    });
    if (!deleted.count) throw notFound('Notification not found.');
    return sendSuccess(res, { deleted: true }, {
      message: 'Notification deleted.'
    });
  } catch (err) {
    next(err);
  }
};

const createNotification = async (req, res, next) => {
  try {
    const { recipientId, title, message, type } = req.body;
    if (!recipientId || !title || !message) {
      return res.status(400).json({
        success: false,
        message: 'recipientId, title, and message are required.'
      });
    }
    const recipient = await prisma.user.findFirst({
      where: { id: recipientId, academyId: req.academyId }
    });
    if (!recipient) throw notFound('Recipient not found in academy.');
    const notification = await prisma.notification.create({
      data: {
        academyId: req.academyId,
        recipientId,
        title: String(title).trim(),
        message: String(message).trim(),
        type: type || 'general'
      }
    });
    return sendSuccess(res, formatNotification(notification), {
      status: 201,
      message: 'Notification sent.'
    });
  } catch (err) {
    next(err);
  }
};

const formatAnnouncement = (announcement) => ({
  id: announcement.id,
  academy_id: announcement.academyId,
  title: announcement.title,
  message: announcement.message,
  target_roles: announcement.targetRoles,
  created_by_uid: announcement.createdById,
  created_by_name: announcement.createdBy?.fullName || '',
  created_at: toIso(announcement.createdAt),
  updated_at: toIso(announcement.updatedAt)
});

const visibleAnnouncementWhere = (req) => {
  if (req.user.role === 'ADMIN') {
    return { academyId: req.academyId };
  }
  const role = req.user.role.toLowerCase();
  return {
    academyId: req.academyId,
    OR: [
      { targetRoles: { has: 'all' } },
      { targetRoles: { has: role } },
      { targetRoles: { has: req.user.role } }
    ]
  };
};

const getAnnouncements = async (req, res, next) => {
  try {
    const announcements = await prisma.announcement.findMany({
      where: visibleAnnouncementWhere(req),
      include: { createdBy: { select: { fullName: true } } },
      orderBy: { createdAt: 'desc' },
      take: Math.min(Number(req.query.limit) || 100, 300)
    });
    return sendSuccess(res, announcements.map(formatAnnouncement));
  } catch (err) {
    next(err);
  }
};

const createAnnouncement = async (req, res, next) => {
  try {
    const { title, message, targetRoles } = req.body;
    if (!title || !message) {
      return res.status(400).json({ success: false, message: 'Title and message are required.' });
    }
    const roles = Array.isArray(targetRoles) && targetRoles.length
      ? targetRoles.map((role) => String(role).toLowerCase())
      : ['all'];

    const announcement = await prisma.announcement.create({
      data: {
        academyId: req.academyId,
        title: String(title).trim(),
        message: String(message).trim(),
        targetRoles: roles,
        createdById: req.user.id
      },
      include: { createdBy: { select: { fullName: true } } }
    });

    // Fan out in-app notifications best-effort: the announcement itself is
    // already saved, so a notification failure must not report a false
    // failure to the caller.
    try {
      const wantsAll = roles.includes('all');
      const roleFilters = wantsAll
        ? ['TEACHER', 'STUDENT', 'PARENT']
        : roles
            .filter((role) => ['teacher', 'student', 'parent'].includes(role))
            .map((role) => role.toUpperCase());
      if (roleFilters.length) {
        const recipients = await prisma.user.findMany({
          where: {
            academyId: req.academyId,
            accountStatus: 'ACTIVE',
            role: { in: roleFilters },
            id: { not: req.user.id }
          },
          select: { id: true }
        });
        if (recipients.length) {
          await prisma.notification.createMany({
            data: recipients.map((recipient) => ({
              academyId: req.academyId,
              recipientId: recipient.id,
              title: 'New Announcement',
              message: announcement.title,
              type: 'announcement'
            }))
          });
        }
      }
    } catch (error) {
      console.error('[Announcement] Notification fan-out failed:', error.message);
    }

    return sendSuccess(res, formatAnnouncement(announcement), {
      status: 201,
      message: 'Announcement created successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const updateAnnouncement = async (req, res, next) => {
  try {
    const existing = await prisma.announcement.findFirst({
      where: { id: req.params.id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Announcement not found in academy.');
    // Ownership: teachers may edit only announcements they created; admins
    // may edit any announcement in their academy.
    if (req.user.role !== 'ADMIN' && existing.createdById !== req.user.id) {
      throw forbidden('You can only edit announcements you created.');
    }
    const data = {};
    if (req.body.title !== undefined) data.title = String(req.body.title).trim();
    if (req.body.message !== undefined) data.message = String(req.body.message).trim();
    if (req.body.targetRoles !== undefined) {
      data.targetRoles = Array.isArray(req.body.targetRoles)
        ? req.body.targetRoles.map((role) => String(role).toLowerCase())
        : ['all'];
    }
    if (!Object.keys(data).length) {
      return res.status(400).json({ success: false, message: 'No announcement fields provided.' });
    }
    const updated = await prisma.announcement.update({
      where: { id: existing.id },
      data,
      include: { createdBy: { select: { fullName: true } } }
    });
    return sendSuccess(res, formatAnnouncement(updated), {
      message: 'Announcement updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteAnnouncement = async (req, res, next) => {
  try {
    const existing = await prisma.announcement.findFirst({
      where: { id: req.params.id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Announcement not found in academy.');
    if (req.user.role !== 'ADMIN' && existing.createdById !== req.user.id) {
      throw forbidden('You can only delete announcements you created.');
    }
    await prisma.announcement.delete({ where: { id: existing.id } });
    return sendSuccess(res, { deleted: true }, {
      message: 'Announcement deleted.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getNotifications,
  createNotification,
  markNotificationRead,
  markAllNotificationsRead,
  deleteNotification,
  getAnnouncements,
  createAnnouncement,
  updateAnnouncement,
  deleteAnnouncement
};
