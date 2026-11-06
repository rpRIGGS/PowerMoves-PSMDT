# Parsons Rehabilitation Center — SAMS / SADOJ integration planning notes

Status: design reference only. No MDT implementation priority change.

## Facility
- Independent small psychiatric/rehabilitation facility under SAMS oversight.
- Existing QBCore job: `parsonsmed` (type `ems`), in `planning-reference/development-jobs.lua`.
- Custom Parsons MLO: secure perimeter/fence, gate and guard shack, individual patient rooms.
- Future `qb-parsons` is planned as an adaptation of `qb-prison`, separate from actual prison records.
- Voluntary residential, involuntary 72-hour evaluation holds, court-ordered continued treatment, and possible outpatient services (substance use, counseling, gambling).
- Staff clock in/out independently. Grade 10 Psychiatrist can independently evaluate/admit patients and initiate holds when permitted under PowerMoves law, consult at other hospitals and coordinate referrals/transfers. Higher administrative grade alone does not grant clinical authority.
- Holds use actual elapsed time including offline time; activities do not shorten holds. Expiration does not override valid extensions/orders. Escape does not delete the record.

## Proposed record types and workflows
1. Admission: voluntary/involuntary/judicial, source, consent/legal basis, responsible clinician, assigned room.
2. Involuntary evaluation hold: initiating authority, justification, start/end timestamps, evaluations, status, review.
3. Psychiatric evaluation: assessment, findings, recommendations, clinician.
4. Treatment plan: goals, assigned providers, counseling, medication and follow-up as appropriate.
5. Counseling sessions: individual/group, substance-use and gambling treatment, progress notes.
6. Nursing/behavioral observations and clinical progress notes.
7. Hospital consultation, referral, transfer and acceptance records.
8. Continued commitment: extension requests, orders, review dates, legal basis.
9. Discharge: authorized decision, summary, property return and aftercare.
10. Facility incidents: safety, unauthorized departure/escape, security responses.
11. Patient property intake/storage/return and room assignment history.

## Credentials / certifications to plan
- Medical license and psychiatric specialization for psychiatrists.
- Psychiatric NP credential/authorization, RN/LPN/CNA nursing credentials.
- Behavioral health / psychiatric technician training.
- Substance use and mental health counseling qualifications, including applicable supervision.
- Facility orientation, safety/de-escalation training, training expiry/renewal and authorization history.
- Store verified credential type, issuer, status, expiry, restrictions and evidence; enforce permissions by qualifications and PowerMoves law, not job grade or `isboss` alone.

## System boundaries
- `qb-parsons`: facility gameplay, admission/room/property state, activity locations, physical access, hold clock, escape handling.
- SAMS.net: confidential medical records, care plans, notes, credentials, audits, medical oversight.
- SADOJ.net: judicial orders, continued commitment and authorized court access.
- SADLE.net: limited law-enforcement access for lawful incidents and investigations; no blanket psychiatric record access.
- Integrations should respect existing confidentiality and cross-agency permissions.
- Keep this as future integration planning; do not interrupt ongoing LEO MDT work.
