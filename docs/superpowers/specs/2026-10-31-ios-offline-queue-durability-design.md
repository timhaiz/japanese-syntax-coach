# iOS Offline Answer Queue Durability Design

Date: 2026-10-31
Status: Awaiting user review

## Goal

Prevent the native iOS client from claiming an answer is safely queued, or sending it to the server, when the local answer-queue write failed. Keep the change limited to the existing `ios-native-app` implementation.

## Current behavior

`OfflineAnswerQueue.enqueue` appends the answer in memory and calls a persistence helper that swallows filesystem errors. `LearningStore.submit` then immediately retries the queue. If the request also fails, the UI reports that the answer remains queued even though it may disappear on process termination.

## Proposed behavior

- Queue persistence remains atomic and user-scoped.
- Queue mutations keep their in-memory contents if the disk write fails, but expose that they are not durable.
- On enqueue persistence failure, `LearningStore` enters a distinct storage-error state and does not start the network submission.
- The existing retry action first flushes the complete in-memory queue to disk. It may contact the API only after that flush succeeds.
- A failed flush keeps the answer in memory, keeps the storage-error state visible, and allows another retry.
- Lesson feedback and the shared learning sync status explain that the answer could not be saved locally and that syncing is paused. They must not say the answer is durably queued.
- Once persistence succeeds, existing server acknowledgement and idempotency behavior remains unchanged.

## Components and boundaries

- `OfflineAnswerQueue`: return or throw on persistence failure; track whether the current in-memory contents are durable; provide an explicit flush operation used before network retries.
- `LearningStore`: map queue-storage failure to a user-visible sync state, prevent network retry until flush succeeds, and preserve the normal API error/success behavior after that gate.
- Learning sync UI: render the storage-error message and retain the existing retry affordance.

No Next.js API, database schema, Supabase auth, StoreKit, or App Store release behavior changes are included.

## Error handling and data flow

1. A user submits an answer; the queue adds it in memory and attempts an atomic disk write.
2. If the write succeeds, `LearningStore` may proceed with the normal API submission.
3. If the write fails, the answer remains in memory for the current process, sync enters storage-error, and the API is not called.
4. When the user retries, the queue attempts to persist all pending answers first. Failure leaves sync paused. Success allows the normal FIFO API retry.
5. Server confirmation and duplicate acknowledgement continue to remove an answer under the existing idempotency contract.

## Tests and acceptance criteria

- A filesystem failure during enqueue produces a storage failure and does not invoke the API retry operation.
- A later successful flush persists the answer and allows the API retry to proceed.
- Repeated flush failure keeps the answer in memory and reports non-durable state.
- Existing FIFO order, stable request IDs, failure retention, and successful-removal tests continue to pass.
- The lesson and shared sync status display the storage error and retry action without claiming durable queueing.
- No backend or release files change.

## Validation constraints

The current machine has Command Line Tools selected instead of full Xcode, and `xcodegen` is not installed. XCTest and Simulator build validation therefore require a later environment with Xcode and XcodeGen configured. This constraint does not change the acceptance criteria; any unavailable check must be reported as skipped rather than passed.
