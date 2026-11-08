const sendSuccess = (res, data, options = {}) => {
  const { status = 200, message } = options;
  const payload = { success: true };
  if (message) payload.message = message;
  if (data !== undefined) payload.data = data;
  return res.status(status).json(payload);
};

const sendError = (res, status, code, message, details) => {
  const payload = { success: false, code, message };
  if (details !== undefined) payload.details = details;
  return res.status(status).json(payload);
};

module.exports = { sendSuccess, sendError };
