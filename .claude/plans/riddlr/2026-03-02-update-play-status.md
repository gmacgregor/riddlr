Review this file and perform the necessary updates to accomplish what is being asked. You must also update any associated test files:

- if a riddle moves from draft to published status
  if live date is set:
  1. is play status closed? -> set status as scheduled and schedule worker
  2. is play status scheduled? -> schedule worker to move to ready status
  3. is play status ready? -> schedule worker to move to live status
  4. is play status live? -> when first correct answer is provided, set play status to completed
  5. is play status completed? -> allow a 3 min cool down period, then set play status to archived
- else:
  - do not modify play status

- as the riddle play status gets updated, the status should be reflectd in the admin listing page i.e. /admin/riddles/, and on the admin edit page for that riddle i.e. /admin/riddles/11/edit
