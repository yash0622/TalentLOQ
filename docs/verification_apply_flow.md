# Application Visibility Verification Flow

This checklist ensures that when a student applies to a drive, the application state is immediately reflected correctly across all relevant screens for both the student and the recruiter.

### Prerequisites
- One recruiter account
- Two distinct student accounts (Student A, Student B)
- Both students must have a resume uploaded in their profile to apply
- One published placement drive (Drive X)

### Verification Steps

- [ ] **1. Instant State Update (Student)**
  - Log in as Student A and navigate to Drive X's detail screen (`DriveDetailScreen`).
  - Tap "Apply".
  - **Verify**: The Apply button changes to a disabled "Applied" state *immediately* without requiring a pull-to-refresh or screen reload.

- [ ] **2. Cache Invalidation (Student)**
  - Navigate back from Drive X to the `OpportunitiesScreen` (drive list).
  - Navigate *back into* Drive X's detail screen.
  - **Verify**: The screen still shows the "Applied" state (it did not revert to an unapplied state due to a stale cache hit).

- [ ] **3. My Applications List**
  - Navigate to the `MyApplicationsScreen`.
  - **Verify**: Drive X appears in the list of active applications *without* needing a manual pull-to-refresh.

- [ ] **4. Recruiter Applicant List (Immediate Reflection)**
  - Log in as the recruiter who posted Drive X.
  - Navigate to Drive X's applicant list (`ApplicantsScreen`).
  - **Verify**: Student A appears in the applicant list immediately.

- [ ] **5. Recruiter Applicant Count (Aggregation check)**
  - Navigate to the recruiter's `MyDrivesScreen` (drive list).
  - **Verify**: The applicant count badge for Drive X accurately reflects the new application (e.g., if it was 0, it is now 1).

- [ ] **6. Application Isolation (Other Students)**
  - Log in as Student B.
  - Navigate to Drive X's detail screen.
  - **Verify**: The screen shows as NOT applied (the "Apply" button is active). Student A's application did not leak into Student B's state.

- [ ] **7. Multi-Applicant Count Increment**
  - As Student B, apply to Drive X.
  - Log back in as the recruiter and check the `MyDrivesScreen`.
  - **Verify**: The applicant count for Drive X is now exactly 2.
  - Check the `ApplicantsScreen`.
  - **Verify**: Both Student A and Student B appear in the list.

### Implementation Notes

- **`applicant_count`**: The total applicant count on the recruiter's list view (`GET /recruiter/drives`) is computed **live via MongoDB aggregation** (`$sum`) over the `applications` collection on every request. It is NOT maintained as a stored counter on the drive document. This ensures the count can never drift out of sync with the actual applications, eliminating race conditions or eventual-consistency bugs at the cost of a slightly more expensive read.
- **Frontend State**: The `ApplicationVisibilityState` ChangeNotifier broadcasts successful application events across the app, ensuring that previously mounted screens (like `MyApplicationsScreen` or cached detail views) invalidate their data or optimistically update immediately.
