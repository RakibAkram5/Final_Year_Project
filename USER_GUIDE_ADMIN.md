# Admin guide

## Getting started
1. **Sign up → Register academy.** You become the academy's admin; share the academy code with staff and families.
2. **Academy info** (business icon or "⋮ → Academy info" on small phones): name, address, phone, then **Set location on map** — search an address, tap the map to adjust the pin or use your current position, and save. Parents and students then see the map and a *Directions* button.
3. **Payment settings** (Fees section): provider, account title, bank name, account number, **IBAN** (checked automatically), instructions for parents, and an optional payment **QR** image (PNG/JPEG ≤ 512 KB). Turn on "enabled" to show them to families.

## People
- **Approval requests:** approve or reject self-registered teachers, students and parents.
- **User Management:** add users directly, edit, reset passwords, deactivate/reactivate.
- **Link parents to children:** edit a parent and pick the students, or handle the requests parents send from their app under **Parent Link Requests** on the dashboard (approve creates the link; reject can carry a note). Parents can never link themselves.
- **Academy Branding** (Academy section): name, address, phone, contact e-mail and the academy **logo** (PNG/JPEG/WebP). The logo appears on the login screen, in every portal and on challan and report PDFs; remove it to fall back to the TaleemPlus mark.
- **Documents:** on a student or teacher card, tap **Documents** (or "⋮ → Documents") to upload admission papers, certificates, CVs (PDF, Word, Excel, PowerPoint, images, text; ≤ 4 MB each). Students and their linked parents can view student documents; only the teacher sees their own.

## Classes and timetable
- **Academic Structure** → define classes and programmes; **Classes & Sections** → create sections and enrol students once per section.
- **Class Management → New Class** → choose class, section, subject and teacher; the section's students are enrolled automatically.
- **Timetable** → add slots; the app refuses slots that double-book a teacher or class.

## Fees
**Generate Challans** creates the month's challans for a whole section in one step (students who already have one for that month, or whose account is inactive, are skipped and counted). From **Class Fee Status** you can print or download any challan (status, month, bank details and QR included). Review **payment proofs** (approving one marks the challan paid — uploading a proof never does), view the ledger and unpaid students.

## Reports & exports
Dashboard → **Reports & Exports**: choose a class and dates →
attendance **PDF/Excel**, results **PDF/Excel**; fee records **Excel** by billing month.

## AI Insights
Shows the fee-risk and performance model status. **Train / Retrain** starts a background job; the page updates when it finishes. Models need at least 100 labelled records; until then the page says *Not enough data yet*. The revenue estimate is a fixed-assumption heuristic, not ML. **Analytics** charts attendance, fees and marks from your academy's own records (filter by dates, section and level) and overlays model predictions when a model is in production. If the backend is not connected to the ML service the pages say *ML service not available* — see `KNOWN_LIMITATIONS.md`.

## Online tests
Teachers create them; you can open any test from **Quiz Reports** → *Online submissions & grading* to see every student's attempt and grade written answers yourself.
