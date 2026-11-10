const crypto = require('crypto');
const prisma = require('../config/db');
const { canReadStudent } = require('../utils/studentAccess');

const MAX_IMAGE_BYTES = 512 * 1024;

function decodeImage(data, mimeType) {
  if (!['image/png', 'image/jpeg'].includes(mimeType) || typeof data !== 'string') return null;
  const encoded = data.replace(/^data:image\/(png|jpeg);base64,/i, '');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) return null;
  const bytes = Buffer.from(encoded, 'base64');
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) return null;
  const isPng = mimeType === 'image/png' && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const isJpeg = mimeType === 'image/jpeg' && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[bytes.length - 2] === 0xff && bytes[bytes.length - 1] === 0xd9;
  return isPng || isJpeg ? bytes : null;
}

/** ISO 13616 IBAN check (mod-97). Accepts spaces; returns normalised IBAN or null. */
function normalizeIban(value) {
  const iban = String(value).replace(/\s+/g, '').toUpperCase();
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$/.test(iban)) return null;
  if (iban.startsWith('PK') && iban.length !== 24) return null;
  const rearranged = iban.slice(4) + iban.slice(0, 4);
  let remainder = 0;
  for (const ch of rearranged) {
    const digits = /[A-Z]/.test(ch) ? String(ch.charCodeAt(0) - 55) : ch;
    for (const d of digits) remainder = (remainder * 10 + Number(d)) % 97;
  }
  return remainder === 1 ? iban : null;
}

const getSettings = async (req, res, next) => {
  try {
    const academy = await prisma.academy.findUnique({
      where: { id: req.academyId },
      select: {
        name: true, paymentQrData: true, paymentQrMimeType: true,
        paymentProvider: true, paymentAccountTitle: true,
        paymentAccountDetails: true, paymentQrEnabled: true,
        bankName: true, bankAccountNumber: true, bankIban: true, paymentInstructions: true,
      },
    });
    if (!academy) return res.status(404).json({ success: false, message: 'Academy not found.' });
    res.json({ success: true, data: {
      academyName: academy.name,
      qrImageBase64: academy.paymentQrData?.toString('base64') || null,
      qrMimeType: academy.paymentQrMimeType,
      provider: academy.paymentProvider,
      accountTitle: academy.paymentAccountTitle,
      accountDetails: academy.paymentAccountDetails,
      enabled: academy.paymentQrEnabled,
      bankName: academy.bankName,
      bankAccountNumber: academy.bankAccountNumber,
      bankIban: academy.bankIban,
      paymentInstructions: academy.paymentInstructions,
    } });
  } catch (err) { next(err); }
};

const updateSettings = async (req, res, next) => {
  try {
    const { qrImageBase64, qrMimeType, provider, accountTitle, accountDetails, enabled,
      bankName, bankAccountNumber, bankIban, paymentInstructions } = req.body;
    if (typeof enabled !== 'boolean') return res.status(400).json({ success: false, message: 'enabled must be a boolean.' });
    for (const [key, value, max] of [
      ['provider', provider, 60], ['accountTitle', accountTitle, 120], ['accountDetails', accountDetails, 220],
      ['bankName', bankName, 80], ['bankAccountNumber', bankAccountNumber, 34],
      ['bankIban', bankIban, 40], ['paymentInstructions', paymentInstructions, 1000],
    ]) {
      if (value != null && (typeof value !== 'string' || value.length > max)) {
        return res.status(400).json({ success: false, message: `Invalid ${key}.` });
      }
    }
    if (bankAccountNumber && !/^[0-9][0-9 -]{5,32}$/.test(bankAccountNumber.trim())) {
      return res.status(400).json({ success: false, message: 'Account number may contain only digits, spaces and dashes.' });
    }
    let iban = null;
    if (bankIban && bankIban.trim()) {
      iban = normalizeIban(bankIban);
      if (!iban) return res.status(400).json({ success: false, message: 'The IBAN is not valid (check the length and digits).' });
    }
    let imageUpdate = {};
    if (qrImageBase64 === null) imageUpdate = { paymentQrData: null, paymentQrMimeType: null };
    else if (qrImageBase64 !== undefined) {
      const bytes = decodeImage(qrImageBase64, qrMimeType);
      if (!bytes) return res.status(400).json({ success: false, message: 'QR image must be a valid PNG or JPEG under 512 KB.' });
      imageUpdate = { paymentQrData: bytes, paymentQrMimeType: qrMimeType };
    }
    const hasBank = Boolean(String(bankAccountNumber || '').trim() || iban);
    if (enabled && !String(accountDetails || '').trim() && !hasBank) {
      return res.status(400).json({ success: false, message: 'Add verified payment account details before enabling payment instructions.' });
    }
    await prisma.academy.update({
      where: { id: req.academyId },
      data: {
        paymentProvider: provider?.trim() || null,
        paymentAccountTitle: accountTitle?.trim() || null,
        paymentAccountDetails: accountDetails?.trim() || null,
        paymentQrEnabled: enabled,
        ...(bankName !== undefined ? { bankName: bankName?.trim() || null } : {}),
        ...(bankAccountNumber !== undefined ? { bankAccountNumber: bankAccountNumber?.trim() || null } : {}),
        ...(bankIban !== undefined ? { bankIban: iban } : {}),
        ...(paymentInstructions !== undefined ? { paymentInstructions: paymentInstructions?.trim() || null } : {}),
        ...imageUpdate,
      },
    });
    res.json({ success: true, message: 'Academy payment settings saved.' });
  } catch (err) { next(err); }
};

const submitProof = async (req, res, next) => {
  try {
    const { id: challanId } = req.params;
    const challan = await prisma.feeChallan.findFirst({
      where: { id: challanId, academyId: req.academyId },
      select: { id: true, studentId: true, status: true },
    });
    if (!challan) return res.status(404).json({ success: false, message: 'Challan not found in this academy.' });
    if (!(await canReadStudent(req, challan.studentId))) return res.status(403).json({ success: false, message: 'You cannot submit proof for this challan.' });
    if (challan.status === 'PAID') return res.status(409).json({ success: false, message: 'This challan is already paid.' });
    const bytes = decodeImage(req.body.imageBase64, req.body.mimeType);
    if (!bytes) return res.status(400).json({ success: false, message: 'Payment proof must be a valid PNG or JPEG under 512 KB.' });
    const pending = await prisma.feePaymentProof.findFirst({ where: { challanId, status: 'PENDING' }, select: { id: true } });
    if (pending) return res.status(409).json({ success: false, message: 'A payment proof is already waiting for review.' });
    const proof = await prisma.feePaymentProof.create({ data: {
      id: crypto.randomUUID(), academyId: req.academyId, challanId,
      submittedById: req.user.id, imageData: bytes, mimeType: req.body.mimeType,
    }, select: { id: true, status: true, submittedAt: true } });
    res.status(201).json({ success: true, data: proof });
  } catch (err) { next(err); }
};

const listPendingProofs = async (req, res, next) => {
  try {
    const proofs = await prisma.feePaymentProof.findMany({
      where: { academyId: req.academyId, status: 'PENDING' },
      include: { challan: { select: { challanNumber: true, studentName: true, totalAmount: true } } },
      orderBy: { submittedAt: 'asc' },
      take: 5,
    });
    res.json({ success: true, data: proofs.map((p) => ({
      id: p.id, status: p.status, submittedAt: p.submittedAt,
      mimeType: p.mimeType, imageBase64: p.imageData.toString('base64'),
      challanNumber: p.challan.challanNumber, studentName: p.challan.studentName,
      amount: Number(p.challan.totalAmount),
    })) });
  } catch (err) { next(err); }
};

const reviewProof = async (req, res, next) => {
  try {
    const { status } = req.body;
    if (!['VERIFIED', 'REJECTED'].includes(status)) return res.status(400).json({ success: false, message: 'Review status must be VERIFIED or REJECTED.' });
    const result = await prisma.$transaction(async (tx) => {
      const proof = await tx.feePaymentProof.findFirst({ where: { id: req.params.id, academyId: req.academyId, status: 'PENDING' } });
      if (!proof) return null;
      const updated = await tx.feePaymentProof.update({
        where: { id: proof.id },
        data: { status, reviewedById: req.user.id, reviewedAt: new Date() },
        select: { id: true, status: true, reviewedAt: true },
      });
      if (status === 'VERIFIED') await tx.feeChallan.update({
        where: { id: proof.challanId },
        data: { status: 'PAID', paidAt: new Date() },
      });
      return updated;
    });
    if (!result) return res.status(404).json({ success: false, message: 'Pending payment proof not found in this academy.' });
    res.json({ success: true, data: result });
  } catch (err) { next(err); }
};

module.exports = {
  normalizeIban, getSettings, updateSettings, submitProof, listPendingProofs, reviewProof };
