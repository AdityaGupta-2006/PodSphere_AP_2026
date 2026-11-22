# CP4: Query Performance, Execution Plans, and Indexing Analysis

| Course | Project | Team | Team Size | Database | Submission Period |
| :--- | :--- | :--- | :---: | :--- | :--- |
| Database Management Systems | PodSphere | T0093 | 4 | PostgreSQL 18.7 (Homebrew) | November 2026 |

## Team Members

| Role | Name | Enrollment No. | GitHub |
| :--- | :--- | :--- | :--- |
| Group Lead | Aniket Kumar | 2501010635 | [NopePlague](https://github.com/NopePlague) |
| Member 2 | Aditya Kumar Gupta | 2501010565 | [AdityaGupta-2006](https://github.com/AdityaGupta-2006) |
| Member 3 | Anik Kumar Deo | 2501010056 | [Source-sucker](https://github.com/Source-sucker) |
| Member 4 | Muskan Praveen | 251010602 | [mukku2549](https://github.com/mukku2549) |

---

## 1. Introduction and Objectives

The final phase of the PodSphere database engineering project (**Checkpoint 4**) evaluates the computational efficiency, query execution characteristics, and indexing efficacy of the application workload across all 23 relational tables defined in `dbms/03_schema.sql` and implemented in `dbms/04_queries.sql`.

In earlier milestones, we designed a normalized 3NF schema (CP1), implemented physical DDL with integrity constraints, table checks, and partial indexes (CP2), and formulated comprehensive read/write SQL query workloads (CP3). The primary objective of CP4 is to shift from theoretical SQL construction to **empirical query performance analysis** using the PostgreSQL cost-based query optimizer (CBO).

### Key Objectives
1. **Empirical Execution Profiling:** Collect real runtime statistics (Planning Time, Execution Time, Top-Level Execution Buffers, Planning Buffers, Memory Consumption) for representative `SELECT` queries across all functional domains using `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`.
2. **Plan Operator Analysis:** Inspect and explain PostgreSQL internal operators, including sequential table scans (`Seq Scan`), B-Tree index scans (`Index Scan`, `Index Only Scan`, `Bitmap Index Scan`), join algorithms (`Nested Loop`, `Hash Join`, `Merge Join`), and memory sorting algorithms (`quicksort`, `top-N heapsort`).
3. **Indexing Evaluation:** Systematically evaluate whether the indexes defined in `dbms/03_schema.sql` effectively accelerate candidate queries, identify missing index opportunities, and empirically verify the performance impact before and after index creation.
4. **Bottleneck & Anomaly Detection:** Pinpoint comparatively expensive queries, diagnose structural bottlenecks such as the Cartesian product fan-out trap in multi-table one-to-many aggregations, and demonstrate query rewrite optimizations.
5. **Artifact Preservation:** Provide reproducible evidence by archiving raw PostgreSQL execution plans as plain text files in the `dbms/plans/` directory.

---

## 2. PostgreSQL Environment and Testing Methodology

### Hardware & Host Architecture
- **Platform:** Apple Mac (Apple Silicon M4, `Mac16,1`)
- **Processor Architecture:** `aarch64` (64-bit ARM)
- **Operating System:** macOS Darwin 27.2.0
- **Storage:** High-throughput Apple NVMe SSD (Unified Memory Architecture)

### PostgreSQL Server Configuration
All benchmarks were conducted against a local PostgreSQL server instance with the following active configuration:

| Configuration Parameter | Active Setting | Unit / Context | Description |
| :--- | :--- | :--- | :--- |
| `server_version` | `18.7 (Homebrew)` | Internal | PostgreSQL 18.7 compiled with Apple clang |
| `shared_buffers` | `16384` (128 MB) | 8 kB pages | Shared memory buffer pool for caching table/index pages |
| `work_mem` | `4096` (4 MB) | kB | Memory space dedicated for internal sort operations and hash tables |
| `maintenance_work_mem` | `65536` (64 MB) | kB | Memory allocated for DDL tasks (e.g. `CREATE INDEX`, `VACUUM`) |
| `effective_cache_size` | `524288` (4096 MB) | 8 kB pages | Planner assumption of available kernel disk cache |
| `seq_page_cost` | `1.0` | Cost Units | Arbitrary reference cost for sequential disk page fetch |
| `random_page_cost` | `4.0` | Cost Units | Relative cost estimate for random disk page access |
| `default_statistics_target` | `100` | Sample Buckets | Sample size for histogram statistics in `pg_statistic` |
| `max_parallel_workers_per_gather` | `2` | Workers | Upper limit on parallel background workers per query |

### Testing Methodology
To ensure that benchmarks are statistically valid, non-destructive, and strictly reproducible, we adopted the following protocol:

1. **Non-Destructive Read Workload:** We evaluated representative `SELECT` queries from `dbms/04_queries.sql`. Destructive `INSERT`, `UPDATE`, and `DELETE` queries were not executed during timing collection to maintain a stable, uniform test state.
2. **Parameter Substitution:** Placeholders (`$1`, `$2`, etc.) were bound to representative IDs and values that reflect realistic application workloads (e.g. valid active user IDs, published course IDs, equipment listing IDs).
3. **Warm Buffer Cache Profiling:** Queries were executed in a pre-warmed state to eliminate operating system page fault cold-start jitter and reflect normal steady-state web application serving conditions. Shared buffer hit ratios were recorded.
4. **Statistics Freshness:** The database was fully analyzed using `ANALYZE;` prior to timing collection to ensure `pg_statistic` and `pg_class.reltuples` contained up-to-date distribution histograms for the Cost-Based Optimizer.
5. **Cost vs Actual Timing Disambiguation:** In this report, planner **Estimated Cost** (expressed in arbitrary cost units derived from `seq_page_cost` and CPU operator costs) is strictly distinguished from **Actual Time** (measured in wall-clock milliseconds by CPU high-resolution timers).
6. **Buffer Accounting Standards:** Buffer counts strictly record the **top-level execution buffers** (representing the total physical 8 kB page accesses in the execution tree), while **planning buffers** are reported separately.

---

## 3. Database Setup and Data Scale

To enable the PostgreSQL cost-based optimizer to select realistic query plans (e.g. index scans, bitmap scans, hash joins, and memory sorts rather than trivial 0-row sequential scans), a realistic test dataset comprising **61,125 records** across all 23 relational tables was seeded into the `podsphere` database.

### Table Row Count Distribution

| Domain | Relational Table | Row Count | Primary Key / Indexing Baseline |
| :--- | :--- | :---: | :--- |
| Identity & Roles | `users` | 2,000 | PK (`user_id`), UK (`email`) |
| Identity & Roles | `roles` | 5 | PK (`role_id`), UK (`role_name`) |
| Identity & Roles | `user_roles` | 3,310 | Composite PK (`user_id`, `role_id`), Index (`role_id`) |
| Identity & Roles | `profiles` | 2,000 | PK (`profile_id`), Unique FK (`user_id`) |
| Podcasts | `podcasts` | 600 | PK (`podcast_id`), FK Index (`creator_id`) |
| Podcasts | `episodes` | 6,000 | PK (`episode_id`), Composite UK (`podcast_id`, `episode_number`) |
| Learning | `courses` | 250 | PK (`course_id`), FK Index (`instructor_id`) |
| Learning | `lessons` | 2,500 | PK (`lesson_id`), Composite UK (`course_id`, `lesson_order`) |
| Learning | `enrollments` | 2,000 | PK (`enrollment_id`), Composite UK (`user_id`, `course_id`), FK Index (`course_id`) |
| Learning | `lesson_progress` | 9,600 | Composite PK (`user_id`, `lesson_id`), FK Index (`lesson_id`) |
| Equipment | `equipment_categories` | 10 | PK (`category_id`), UK (`category_name`) |
| Equipment | `equipment` | 600 | PK (`equipment_id`), FK Indexes (`provider_id`, `category_id`) |
| Equipment | `rentals` | 3,500 | PK (`rental_id`), FK Indexes (`equipment_id`, `renter_id`), Partial Index (`inventory_window`) |
| Studios | `studios` | 150 | PK (`studio_id`), FK Index (`provider_id`) |
| Studios | `studio_bookings` | 2,000 | PK (`booking_id`), GiST Exclusion Constraint, FK Indexes (`studio_id`, `customer_id`) |
| Creator Services | `services` | 400 | PK (`service_id`), FK Index (`provider_id`) |
| Creator Services | `service_orders` | 3,000 | PK (`service_order_id`), FK Indexes (`service_id`, `customer_id`) |
| Finance | `payments` | 6,000 | PK (`payment_id`), FK Index (`payer_id`), Partial UK (`payment_reference`) |
| Finance | `transactions` | 8,000 | PK (`transaction_id`), FK Index (`payment_id`), Partial UK (`provider_reference`) |
| Finance | `payouts` | 1,200 | PK (`payout_id`), FK Index (`provider_id`), Partial UK (`payout_reference`) |
| Feedback | `reviews` | 5,000 | PK (`review_id`), FK Index (`reviewer_id`), 5 Target Partial UKs |
| Creator Planning | `creator_plans` | 500 | PK (`plan_id`), FK Index (`creator_id`) |
| Creator Planning | `plan_tasks` | 2,500 | PK (`task_id`), Composite UK (`plan_id`, `task_order`), FK Index (`plan_id`) |
| **Total** | **All 23 Tables** | **61,125** | **63 Table & Constraint Indexes Verified** |

### Data Generation Guarantees & Assumptions
- **Referential Integrity:** All foreign key constraints are strictly satisfied. No orphaned records exist.
- **Database Triggers Enforced:** Seeding logic verified compliance with `trg_rentals_inventory` (no overbooked confirmed rentals), `trg_studio_bookings_no_confirmed_overlap` (GiST exclusion range non-overlap), and `trg_lesson_progress_requires_enrollment` (every progress record references a verified active/completed course enrollment).
- **Realistic Cardinality Distribution:** Active creators own 1 to 3 podcasts with 10 episodes each; courses contain 10 curriculum lessons; learners are enrolled in multiple courses with progressive lesson completions; reviews target exactly one valid entity.

---

## 4. Query-Wise Execution Time Analysis

Below is the consolidated benchmark summary of **28 representative SELECT queries** selected from all 12 functional sections of `dbms/04_queries.sql`. Each plan was captured using `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` and archived in `dbms/plans/`. Buffer accounting reports the top-level execution buffer hits alongside planning buffers separately.

| Query ID | Functional Title & Domain | Execution Plan File | Plan Time (ms) | Exec Time (ms) | Planner Estimated Cost | Actual Time (ms) | Actual Rows | Execution Buffers (hit) | Planning Buffers (hit) |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `Q01` | Authenticate user by canonical lowercase email to retrieve credentials | [`q01_auth_credentials.txt`](plans/q01_auth_credentials.txt) | 0.183 | 0.018 | `0.28..8.29` | 0.010..0.011 | 1 | 3 | 94 |
| `Q02` | Fetch authenticated user account details along with profile and all assigned roles | [`q02_user_account_details.txt`](plans/q02_user_account_details.txt) | 0.620 | 0.110 | `22.16..22.19` | 0.069..0.069 | 1 | 19 | 356 |
| `Q03` | Verify if a user holds a specific named role | [`q03_verify_user_role.txt`](plans/q03_verify_user_role.txt) | 0.350 | 0.057 | `5.40..5.41` | 0.035..0.035 | 1 | 7 | 241 |
| `Q04` | Fetch podcast details by ID with creator profile and total episode count | [`q04_podcast_details_by_id.txt`](plans/q04_podcast_details_by_id.txt) | 0.598 | 0.113 | `51.18..51.43` | 0.065..0.066 | 1 | 27 | 373 |
| `Q05` | Browse and search active podcasts with category, language filters, and pagination | [`q05_browse_active_podcasts.txt`](plans/q05_browse_active_podcasts.txt) | 1.048 | 1.145 | `402.68..402.70` | 1.101..1.104 | 10 | 426 | 319 |
| `Q06` | List published episodes for a podcast ordered by episode number | [`q06_list_published_episodes.txt`](plans/q06_list_published_episodes.txt) | 0.168 | 0.039 | `38.04..38.06` | 0.024..0.025 | 8 | 18 | 134 |
| `Q07` | Browse published courses with instructor details, lesson counts, and aggregate reviews | [`q07_browse_published_courses.txt`](plans/q07_browse_published_courses.txt) | 1.983 | 7.389 | `2782.46..2782.49` | 7.313..7.315 | 10 | 4554 | 456 |
| `Q08` | Fetch course details by ID with instructor profile and active enrollment count | [`q08_course_details_by_id.txt`](plans/q08_course_details_by_id.txt) | 1.565 | 0.710 | `96.06..108.06` | 0.644..0.645 | 1 | 45 | 564 |
| `Q09` | List lessons for a course with authenticated learner's completion status | [`q09_course_lessons_with_progress.txt`](plans/q09_course_lessons_with_progress.txt) | 0.347 | 0.124 | `51.98..52.01` | 0.075..0.077 | 10 | 26 | 262 |
| `Q10` | List all courses a learner is enrolled in along with progress completion percentage | [`q10_learner_enrolled_courses.txt`](plans/q10_learner_enrolled_courses.txt) | 1.367 | 0.184 | `23.26..23.66` | 0.121..0.122 | 1 | 55 | 381 |
| `Q11` | Browse available equipment catalog with category, provider details, and review metrics | [`q11_browse_available_equipment.txt`](plans/q11_browse_available_equipment.txt) | 2.547 | 0.636 | `10.56..22.08` | 0.504..0.516 | 10 | 224 | 464 |
| `Q12` | Calculate available inventory for an equipment listing across an overlapping date range | [`q12_equipment_available_inventory.txt`](plans/q12_equipment_available_inventory.txt) | 1.402 | 0.134 | `4.58..20.71` | 0.055..0.056 | 1 | 13 | 301 |
| `Q13` | List rental history for a renter | [`q13_rental_history_by_renter.txt`](plans/q13_rental_history_by_renter.txt) | 1.821 | 0.135 | `29.16..29.16` | 0.068..0.069 | 1 | 18 | 446 |
| `Q14` | List rental requests received for provider's equipment | [`q14_rental_requests_by_provider.txt`](plans/q14_rental_requests_by_provider.txt) | 2.072 | 0.357 | `62.25..62.28` | 0.283..0.285 | 11 | 81 | 452 |
| `Q15` | Browse available studios with provider profile and review rating | [`q15_browse_available_studios.txt`](plans/q15_browse_available_studios.txt) | 2.024 | 0.384 | `7.91..10.37` | 0.196..0.275 | 10 | 173 | 397 |
| `Q16` | Check studio slot availability for overlapping confirmed bookings | [`q16_studio_slot_availability.txt`](plans/q16_studio_slot_availability.txt) | 1.123 | 0.127 | `0.00..15.75` | 0.058..0.078 | 1 | 5 | 184 |
| `Q17` | List studio bookings received by provider | [`q17_provider_studio_bookings.txt`](plans/q17_provider_studio_bookings.txt) | 2.042 | 0.378 | `41.78..41.81` | 0.279..0.281 | 14 | 93 | 418 |
| `Q18` | Browse active creator services with provider details and reviews | [`q18_browse_active_services.txt`](plans/q18_browse_active_services.txt) | 2.258 | 0.271 | `6.71..11.67` | 0.188..0.202 | 10 | 163 | 390 |
| `Q19` | Fetch payment by ID with payer information and associated transaction events | [`q19_payment_transactions_by_id.txt`](plans/q19_payment_transactions_by_id.txt) | 1.548 | 0.148 | `28.52..28.53` | 0.078..0.079 | 2 | 19 | 486 |
| `Q20` | Calculate provider payout summary: total paid out vs currently processing/pending | [`q20_provider_payout_summary.txt`](plans/q20_provider_payout_summary.txt) | 0.741 | 0.144 | `12.20..12.29` | 0.074..0.074 | 1 | 11 | 146 |
| `Q21` | Fetch reviews for a course target with reviewer profile | [`q21_course_reviews_target.txt`](plans/q21_course_reviews_target.txt) | 2.100 | 0.200 | `36.69..36.70` | 0.120..0.121 | 4 | 33 | 392 |
| `Q22` | Calculate aggregate rating score and star distribution breakdown for an entity | [`q22_review_aggregate_distribution.txt`](plans/q22_review_aggregate_distribution.txt) | 1.013 | 0.130 | `17.88..17.89` | 0.058..0.058 | 1 | 9 | 167 |
| `Q23` | Fetch creator plan by ID with ordered tasks | [`q23_creator_plan_ordered_tasks.txt`](plans/q23_creator_plan_ordered_tasks.txt) | 1.789 | 0.177 | `32.27..32.28` | 0.094..0.095 | 5 | 22 | 379 |
| `Q24` | Creator 360 overview dashboard: podcasts, episodes, courses, enrolled students, and planning status | [`q24_analytics_creator_360.txt`](plans/q24_analytics_creator_360.txt) | 3.405 | 0.393 | `136.79..147.80` | 0.258..0.260 | 1 | 41 | 557 |
| `Q25` | Marketplace provider revenue summary across equipment rentals, studio bookings, and creator services | [`q25_analytics_provider_revenue.txt`](plans/q25_analytics_provider_revenue.txt) | 3.616 | 0.373 | `18.04..134.75` | 0.250..0.253 | 1 | 58 | 685 |
| `Q26` | Course curriculum funnel and learner completion rate by lesson | [`q26_analytics_course_curriculum_funnel.txt`](plans/q26_analytics_course_curriculum_funnel.txt) | 0.541 | 2.055 | `378.07..378.10` | 2.017..2.019 | 10 | 112 | 293 |
| `Q27` | Studio booking utilization and revenue metrics | [`q27_analytics_studio_utilization.txt`](plans/q27_analytics_studio_utilization.txt) | 0.914 | 0.169 | `32.54..32.54` | 0.115..0.116 | 1 | 25 | 255 |
| `Q28` | Equipment fleet utilization and rental activity report | [`q28_analytics_equipment_fleet.txt`](plans/q28_analytics_equipment_fleet.txt) | 1.224 | 0.185 | `55.56..55.59` | 0.129..0.130 | 2 | 32 | 344 |

---

## 5. Domain-by-Domain Execution Plan Deep Dive

This section examines the concrete execution mechanics for representative queries across each functional area of PodSphere.

### 5.1 Authentication & User Account Operations (Section 1 & 3)

#### `Q01`: Authenticate user by canonical lowercase email to retrieve credentials
- **Execution Plan:** [`dbms/plans/q01_auth_credentials.txt`](plans/q01_auth_credentials.txt)
- **Execution Time:** `0.018 ms` | **Planning Time:** `0.183 ms`
- **Optimizer Estimated Cost:** `0.28..8.29` | **Actual Time Range:** `0.010..0.011 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `3` shared hit pages | **Planning Buffers:** `94` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
PostgreSQL executes an Index Scan using the unique index `uq_users_email`. The `lower()` predicate matches the canonical storage index condition directly. The executor traverses 3 shared buffer pages (B-Tree root -> leaf -> table heap page), returning the matched user tuple in 0.018 ms.

#### `Q02`: Fetch authenticated user account details along with profile and all assigned roles
- **Execution Plan:** [`dbms/plans/q02_user_account_details.txt`](plans/q02_user_account_details.txt)
- **Execution Time:** `0.110 ms` | **Planning Time:** `0.620 ms`
- **Optimizer Estimated Cost:** `22.16..22.19` | **Actual Time Range:** `0.069..0.069 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `19` shared hit pages | **Planning Buffers:** `356` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Starts with an Index Scan on `pk_users` for user_id = 42, then traverses three sequential `Nested Loop Left Join` steps against `uq_profiles_user_id`, `pk_user_roles`, and `pk_roles`. An in-memory `GroupAggregate` constructs the string role array via `ARRAY_AGG(r.role_name)`. The query accesses 19 execution buffer pages and completes in 0.110 ms.

#### `Q03`: Verify if a user holds a specific named role
- **Execution Plan:** [`dbms/plans/q03_verify_user_role.txt`](plans/q03_verify_user_role.txt)
- **Execution Time:** `0.057 ms` | **Planning Time:** `0.350 ms`
- **Optimizer Estimated Cost:** `5.40..5.41` | **Actual Time Range:** `0.035..0.035 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `7` shared hit pages | **Planning Buffers:** `241` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Evaluated as an early-exit `Result` node wrapping an `EXISTS` subquery. It probes composite primary key `pk_user_roles(user_id, role_id)` and joins `roles` using `pk_roles` with a filter on `role_name = 'creator'`. Scanning stops immediately upon finding the first matching tuple, executing in 0.057 ms across 7 buffer hits.

### 5.2 Podcast & Episode Operations (Section 4)

#### `Q04`: Fetch podcast details by ID with creator profile and total episode count
- **Execution Plan:** [`dbms/plans/q04_podcast_details_by_id.txt`](plans/q04_podcast_details_by_id.txt)
- **Execution Time:** `0.113 ms` | **Planning Time:** `0.598 ms`
- **Optimizer Estimated Cost:** `51.18..51.43` | **Actual Time Range:** `0.065..0.066 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `27` shared hit pages | **Planning Buffers:** `373` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Performs an Index Scan on `pk_podcasts` (podcast_id = 12), joins `pk_users` and `uq_profiles_user_id` via Nested Loop, and retrieves child episodes using a Bitmap Index Scan on `uq_episodes_podcast_number`. Filtered aggregation counts published vs total episodes in 0.113 ms over 27 buffer hits.

#### `Q05`: Browse and search active podcasts with category, language filters, and pagination
- **Execution Plan:** [`dbms/plans/q05_browse_active_podcasts.txt`](plans/q05_browse_active_podcasts.txt)
- **Execution Time:** `1.145 ms` | **Planning Time:** `1.048 ms`
- **Optimizer Estimated Cost:** `402.68..402.70` | **Actual Time Range:** `1.101..1.104 ms`
- **Rows Returned:** `10` | **Execution Buffers:** `426` shared hit pages | **Planning Buffers:** `319` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
The active podcast discovery feed query. Under baseline indexing, the optimizer performs a sequential scan on `podcasts` with a filter on `status = 'active'`, joins users and episodes, and uses a `top-N heapsort` on `p.created_at DESC` to satisfy `LIMIT 10`. It processes 426 execution buffer hits in 1.145 ms.

#### `Q06`: List published episodes for a podcast ordered by episode number
- **Execution Plan:** [`dbms/plans/q06_list_published_episodes.txt`](plans/q06_list_published_episodes.txt)
- **Execution Time:** `0.039 ms` | **Planning Time:** `0.168 ms`
- **Optimizer Estimated Cost:** `38.04..38.06` | **Actual Time Range:** `0.024..0.025 ms`
- **Rows Returned:** `8` | **Execution Buffers:** `18` shared hit pages | **Planning Buffers:** `134` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Uses the composite index prefix of `uq_episodes_podcast_number` for podcast_id = 12 via a Bitmap Index Scan, filters published episodes, and performs an in-memory quicksort on 8 rows in 0.039 ms across 18 buffer hits.

### 5.3 Learning, Courses, Lessons & Progress Operations (Section 5)

#### `Q07`: Browse published courses with instructor details, lesson counts, and aggregate reviews
- **Execution Plan:** [`dbms/plans/q07_browse_published_courses.txt`](plans/q07_browse_published_courses.txt)
- **Execution Time:** `7.389 ms` | **Planning Time:** `1.983 ms`
- **Optimizer Estimated Cost:** `2782.46..2782.49` | **Actual Time Range:** `7.313..7.315 ms`
- **Rows Returned:** `10` | **Execution Buffers:** `4554` shared hit pages | **Planning Buffers:** `456` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Multi-table catalog query joining `courses` to two independent 1-to-many child tables (`lessons` and `reviews`). This produces a Cartesian product expansion (4,000 joined tuples) before computing `COUNT(DISTINCT)`. This is the most computationally expensive query in the workload (7.389 ms, 4,554 execution buffer hits).

#### `Q08`: Fetch course details by ID with instructor profile and active enrollment count
- **Execution Plan:** [`dbms/plans/q08_course_details_by_id.txt`](plans/q08_course_details_by_id.txt)
- **Execution Time:** `0.710 ms` | **Planning Time:** `1.565 ms`
- **Optimizer Estimated Cost:** `96.06..108.06` | **Actual Time Range:** `0.644..0.645 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `45` shared hit pages | **Planning Buffers:** `564` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Fetches course metadata by primary key, joining instructor profile, lessons, enrollments, and reviews via B-Tree index scans. Aggregates distinct lesson counts, active learners, and average rating in 0.710 ms across 45 execution buffer hits.

#### `Q09`: List lessons for a course with authenticated learner's completion status
- **Execution Plan:** [`dbms/plans/q09_course_lessons_with_progress.txt`](plans/q09_course_lessons_with_progress.txt)
- **Execution Time:** `0.124 ms` | **Planning Time:** `0.347 ms`
- **Optimizer Estimated Cost:** `51.98..52.01` | **Actual Time Range:** `0.075..0.077 ms`
- **Rows Returned:** `10` | **Execution Buffers:** `26` shared hit pages | **Planning Buffers:** `262` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Scans `lessons` using `uq_lessons_course_order` prefix (course_id = 5) and left-joins `lesson_progress` on composite key `pk_lesson_progress(user_id=42, lesson_id)`. Sorts 10 lessons by sequence order in 0.124 ms across 26 buffer hits.

#### `Q10`: List all courses a learner is enrolled in along with progress completion percentage
- **Execution Plan:** [`dbms/plans/q10_learner_enrolled_courses.txt`](plans/q10_learner_enrolled_courses.txt)
- **Execution Time:** `0.184 ms` | **Planning Time:** `1.367 ms`
- **Optimizer Estimated Cost:** `23.26..23.66` | **Actual Time Range:** `0.121..0.122 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `55` shared hit pages | **Planning Buffers:** `381` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Identifies learner enrollments via `uq_enrollments_user_course`, joins courses and lessons, and probes completed lessons to compute progress percentages using a `GroupAggregate` in 0.184 ms across 55 buffer hits.

### 5.4 Equipment Marketplace & Rental Operations (Section 6)

#### `Q11`: Browse available equipment catalog with category, provider details, and review metrics
- **Execution Plan:** [`dbms/plans/q11_browse_available_equipment.txt`](plans/q11_browse_available_equipment.txt)
- **Execution Time:** `0.636 ms` | **Planning Time:** `2.547 ms`
- **Optimizer Estimated Cost:** `10.56..22.08` | **Actual Time Range:** `0.504..0.516 ms`
- **Rows Returned:** `10` | **Execution Buffers:** `224` shared hit pages | **Planning Buffers:** `464` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Filters available equipment listings, joins `equipment_categories` on primary key and `reviews` on `equipment_id`. Results are sorted by equipment_id DESC with pagination (`LIMIT 10`) in 0.636 ms across 224 execution buffer hits.

#### `Q12`: Calculate available inventory for an equipment listing across an overlapping date range
- **Execution Plan:** [`dbms/plans/q12_equipment_available_inventory.txt`](plans/q12_equipment_available_inventory.txt)
- **Execution Time:** `0.134 ms` | **Planning Time:** `1.402 ms`
- **Optimizer Estimated Cost:** `4.58..20.71` | **Actual Time Range:** `0.055..0.056 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `13` shared hit pages | **Planning Buffers:** `301` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Calculates peak reserved inventory over overlapping intervals `[start_date, end_date)` using a `LATERAL` subquery and PostgreSQL `daterange &&` operators. Aggregates boundary check dates in 0.134 ms across 13 execution buffer hits.

#### `Q13`: List rental history for a renter
- **Execution Plan:** [`dbms/plans/q13_rental_history_by_renter.txt`](plans/q13_rental_history_by_renter.txt)
- **Execution Time:** `0.135 ms` | **Planning Time:** `1.821 ms`
- **Optimizer Estimated Cost:** `29.16..29.16` | **Actual Time Range:** `0.068..0.069 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `18` shared hit pages | **Planning Buffers:** `446` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Retrieves rentals for user 42 using `ix_rentals_renter_id` via a Bitmap Index Scan, joins equipment and provider profile, and sorts in memory by `created_at DESC` in 0.135 ms across 18 buffer hits.

#### `Q14`: List rental requests received for provider's equipment
- **Execution Plan:** [`dbms/plans/q14_rental_requests_by_provider.txt`](plans/q14_rental_requests_by_provider.txt)
- **Execution Time:** `0.357 ms` | **Planning Time:** `2.072 ms`
- **Optimizer Estimated Cost:** `62.25..62.28` | **Actual Time Range:** `0.283..0.285 ms`
- **Rows Returned:** `11` | **Execution Buffers:** `81` shared hit pages | **Planning Buffers:** `452` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Scans `equipment` by provider_id using `ix_equipment_provider_id`, joins matching rentals via `ix_rentals_equipment_id`, and orders 11 rental requests in 0.357 ms across 81 execution buffer hits.

### 5.5 Studio Listings & Booking Operations (Section 7)

#### `Q15`: Browse available studios with provider profile and review rating
- **Execution Plan:** [`dbms/plans/q15_browse_available_studios.txt`](plans/q15_browse_available_studios.txt)
- **Execution Time:** `0.384 ms` | **Planning Time:** `2.024 ms`
- **Optimizer Estimated Cost:** `7.91..10.37` | **Actual Time Range:** `0.196..0.275 ms`
- **Rows Returned:** `10` | **Execution Buffers:** `173` shared hit pages | **Planning Buffers:** `397` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Marketplace browse query filtering studios by capacity and hourly rate. Joins provider profile and reviews, sorting via `top-N heapsort` in 0.384 ms across 173 buffer hits.

#### `Q16`: Check studio slot availability for overlapping confirmed bookings
- **Execution Plan:** [`dbms/plans/q16_studio_slot_availability.txt`](plans/q16_studio_slot_availability.txt)
- **Execution Time:** `0.127 ms` | **Planning Time:** `1.123 ms`
- **Optimizer Estimated Cost:** `0.00..15.75` | **Actual Time Range:** `0.058..0.078 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `5` shared hit pages | **Planning Buffers:** `184` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Real-time studio slot availability check. Scans `studio_bookings` using `ix_studio_bookings_studio_id` and checks for range overlap using `tstzrange &&`. Early-exits via `EXISTS` in 0.127 ms across 5 buffer hits.

#### `Q17`: List studio bookings received by provider
- **Execution Plan:** [`dbms/plans/q17_provider_studio_bookings.txt`](plans/q17_provider_studio_bookings.txt)
- **Execution Time:** `0.378 ms` | **Planning Time:** `2.042 ms`
- **Optimizer Estimated Cost:** `41.78..41.81` | **Actual Time Range:** `0.279..0.281 ms`
- **Rows Returned:** `14` | **Execution Buffers:** `93` shared hit pages | **Planning Buffers:** `418` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Provider booking management query. Scans provider studios, joins studio bookings, and calculates duration and revenue for 14 bookings in 0.378 ms across 93 buffer hits.

### 5.6 Creator Services & Order Operations (Section 8)

#### `Q18`: Browse active creator services with provider details and reviews
- **Execution Plan:** [`dbms/plans/q18_browse_active_services.txt`](plans/q18_browse_active_services.txt)
- **Execution Time:** `0.271 ms` | **Planning Time:** `2.258 ms`
- **Optimizer Estimated Cost:** `6.71..11.67` | **Actual Time Range:** `0.188..0.202 ms`
- **Rows Returned:** `10` | **Execution Buffers:** `163` shared hit pages | **Planning Buffers:** `390` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Filters active services, joins provider profiles, and aggregates customer reviews. Paginates via `top-N heapsort` in 0.271 ms across 163 buffer hits.

### 5.7 Finance Operations: Payments, Transactions & Payouts (Section 9)

#### `Q19`: Fetch payment by ID with payer information and associated transaction events
- **Execution Plan:** [`dbms/plans/q19_payment_transactions_by_id.txt`](plans/q19_payment_transactions_by_id.txt)
- **Execution Time:** `0.148 ms` | **Planning Time:** `1.548 ms`
- **Optimizer Estimated Cost:** `28.52..28.53` | **Actual Time Range:** `0.078..0.079 ms`
- **Rows Returned:** `2` | **Execution Buffers:** `19` shared hit pages | **Planning Buffers:** `486` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Payment ledger audit query. Locates payment by primary key, joins payer profile, and reads transaction events via `ix_transactions_payment_id` in 0.148 ms across 19 buffer hits.

#### `Q20`: Calculate provider payout summary: total paid out vs currently processing/pending
- **Execution Plan:** [`dbms/plans/q20_provider_payout_summary.txt`](plans/q20_provider_payout_summary.txt)
- **Execution Time:** `0.144 ms` | **Planning Time:** `0.741 ms`
- **Optimizer Estimated Cost:** `12.20..12.29` | **Actual Time Range:** `0.074..0.074 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `11` shared hit pages | **Planning Buffers:** `146` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Financial payout balance calculation. Performs conditional sums using `FILTER (WHERE status = 'paid')`, `processing`, and `pending` via `ix_payouts_provider_id` in 0.144 ms across 11 buffer hits.

### 5.8 Reviews & Feedback Operations (Section 10)

#### `Q21`: Fetch reviews for a course target with reviewer profile
- **Execution Plan:** [`dbms/plans/q21_course_reviews_target.txt`](plans/q21_course_reviews_target.txt)
- **Execution Time:** `0.200 ms` | **Planning Time:** `2.100 ms`
- **Optimizer Estimated Cost:** `36.69..36.70` | **Actual Time Range:** `0.120..0.121 ms`
- **Rows Returned:** `4` | **Execution Buffers:** `33` shared hit pages | **Planning Buffers:** `392` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Retrieves feedback for a target course using partial unique index `uq_reviews_course_target_reviewer`, joins reviewer profile, and sorts by created_at DESC in 0.200 ms across 33 buffer hits.

#### `Q22`: Calculate aggregate rating score and star distribution breakdown for an entity
- **Execution Plan:** [`dbms/plans/q22_review_aggregate_distribution.txt`](plans/q22_review_aggregate_distribution.txt)
- **Execution Time:** `0.130 ms` | **Planning Time:** `1.013 ms`
- **Optimizer Estimated Cost:** `17.88..17.89` | **Actual Time Range:** `0.058..0.058 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `9` shared hit pages | **Planning Buffers:** `167` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Calculates total reviews, average rating, and counts for 1 through 5 stars for an entity target using conditional filters in 0.130 ms across 9 buffer hits.

### 5.9 Creator Planning & Task Management (Section 11)

#### `Q23`: Fetch creator plan by ID with ordered tasks
- **Execution Plan:** [`dbms/plans/q23_creator_plan_ordered_tasks.txt`](plans/q23_creator_plan_ordered_tasks.txt)
- **Execution Time:** `0.177 ms` | **Planning Time:** `1.789 ms`
- **Optimizer Estimated Cost:** `32.27..32.28` | **Actual Time Range:** `0.094..0.095 ms`
- **Rows Returned:** `5` | **Execution Buffers:** `22` shared hit pages | **Planning Buffers:** `379` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Creator production planning view. Reads plan by primary key, joins creator profile, and scans checklist tasks using `uq_plan_tasks_plan_order` in 0.177 ms across 22 buffer hits.

### 5.10 Business Intelligence, Analytics & Dashboard Reporting (Section 12)

#### `Q24`: Creator 360 overview dashboard: podcasts, episodes, courses, enrolled students, and planning status
- **Execution Plan:** [`dbms/plans/q24_analytics_creator_360.txt`](plans/q24_analytics_creator_360.txt)
- **Execution Time:** `0.393 ms` | **Planning Time:** `3.405 ms`
- **Optimizer Estimated Cost:** `136.79..147.80` | **Actual Time Range:** `0.258..0.260 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `41` shared hit pages | **Planning Buffers:** `557` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Executive creator overview query joining 7 relational tables. Traverses podcasts, episodes, courses, enrollments, plans, and tasks for a creator. Foreign key indexes keep execution time bounded to 0.393 ms across 41 buffer hits.

#### `Q25`: Marketplace provider revenue summary across equipment rentals, studio bookings, and creator services
- **Execution Plan:** [`dbms/plans/q25_analytics_provider_revenue.txt`](plans/q25_analytics_provider_revenue.txt)
- **Execution Time:** `0.373 ms` | **Planning Time:** `3.616 ms`
- **Optimizer Estimated Cost:** `18.04..134.75` | **Actual Time Range:** `0.250..0.253 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `58` shared hit pages | **Planning Buffers:** `685` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Calculates provider revenue across equipment, studios, and services using independent pre-aggregated subqueries. Avoids Cartesian products entirely and executes in 0.373 ms across 58 buffer hits.

#### `Q26`: Course curriculum funnel and learner completion rate by lesson
- **Execution Plan:** [`dbms/plans/q26_analytics_course_curriculum_funnel.txt`](plans/q26_analytics_course_curriculum_funnel.txt)
- **Execution Time:** `2.055 ms` | **Planning Time:** `0.541 ms`
- **Optimizer Estimated Cost:** `378.07..378.10` | **Actual Time Range:** `2.017..2.019 ms`
- **Rows Returned:** `10` | **Execution Buffers:** `112` shared hit pages | **Planning Buffers:** `293` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Analyzes student drop-off across sequential lessons. Joins course lessons with enrollments and lesson progress, aggregating completion percentages in 2.055 ms across 112 buffer hits.

#### `Q27`: Studio booking utilization and revenue metrics
- **Execution Plan:** [`dbms/plans/q27_analytics_studio_utilization.txt`](plans/q27_analytics_studio_utilization.txt)
- **Execution Time:** `0.169 ms` | **Planning Time:** `0.914 ms`
- **Optimizer Estimated Cost:** `32.54..32.54` | **Actual Time Range:** `0.115..0.116 ms`
- **Rows Returned:** `1` | **Execution Buffers:** `25` shared hit pages | **Planning Buffers:** `255` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Computes booked hours and earned revenue per studio. Uses `ix_studios_provider_id` and `ix_studio_bookings_studio_id` in 0.169 ms across 25 buffer hits.

#### `Q28`: Equipment fleet utilization and rental activity report
- **Execution Plan:** [`dbms/plans/q28_analytics_equipment_fleet.txt`](plans/q28_analytics_equipment_fleet.txt)
- **Execution Time:** `0.185 ms` | **Planning Time:** `1.224 ms`
- **Optimizer Estimated Cost:** `55.56..55.59` | **Actual Time Range:** `0.129..0.130 ms`
- **Rows Returned:** `2` | **Execution Buffers:** `32` shared hit pages | **Planning Buffers:** `344` shared hit pages

**Execution Plan Highlights & Node Walkthrough:**
Aggregates rental utilization (unit-days rented) and gross revenue per equipment listing in 0.185 ms across 32 buffer hits.

---

## 6. Detailed Analysis of Execution Plan Operators

An inspection of the captured plans reveals how PostgreSQL translates high-level relational calculus into physical operator trees.

### 6.1 Sequential Scans vs. Index Access Paths
- **`Index Scan`**: Utilized whenever the query predicate matches an indexed column with high selectivity (e.g. `pk_users` in Q01, `uq_profiles_user_id` in Q02, `ix_creator_plans_creator_id` in Q23). The executor traverses B-Tree root and branch pages, accesses the exact heap tuple via its Tuple ID (TID), and touches only 3 to 5 execution buffer pages.
- **`Index Only Scan`**: Encountered when all required output attributes exist in the index leaf pages themselves (e.g. scanning `pk_users(user_id)`). Because no table heap access is required, heap fetches are reported as `0`, maximizing throughput.
- **`Bitmap Index Scan` & `Bitmap Heap Scan`**: When multiple rows match a predicate (e.g. `uq_episodes_podcast_number` for podcast episodes or `ix_rentals_renter_id`), PostgreSQL constructs an in-memory bitmap of physical block offsets. It then performs a sequential-like read of heap blocks in physical disk order, minimizing disk head movement / cache random jumps.
- **`Seq Scan`**: Selected by the optimizer when filtering on unindexed columns or when the predicate matches a high percentage (>20-30%) of table pages (e.g. `podcasts WHERE status = 'active'` in Q05). When sequential scans are followed by sorting, they represent key optimization targets.

### 6.2 Join Mechanisms
- **`Nested Loop Left Join`**: Chosen for point lookups where the outer relation produces a small number of rows (often 1 row from a PK lookup). For each outer row, the inner relation is indexed and probed instantaneously. Used extensively in Q02, Q04, Q08, and Q24.
- **`Hash Join`**: Selected when joining larger unsorted intermediate datasets without matching index order (e.g. Q10 learner courses, Q25 provider revenue subqueries). PostgreSQL builds an in-memory hash table of the inner relation and streams outer rows through it.
- **`Merge Join` / `Merge Left Join`**: Selected when both inputs are pre-sorted on the join keys (either through an index or preceding sort step), as observed in Q07 and Q11. It steps through both inputs simultaneously in `O(N + M)` time.

### 6.3 Aggregation & Sorting Mechanics
- **`GroupAggregate`**: Operates on pre-sorted data. It aggregates rows incrementally as long as the grouping key remains identical, consuming minimal memory (e.g. 25-35 kB). Used in Q02, Q04, Q08, and Q24.
- **`HashAggregate`**: Builds an in-memory hash table for grouping when inputs are not pre-sorted. Used in standalone group-by subqueries.
- **`top-N heapsort`**: When a query contains `ORDER BY ... LIMIT k`, PostgreSQL allocates a bounded heap of size `k` in memory. As rows are scanned, only the top `k` candidates are maintained. This avoids sorting the full dataset, reducing memory overhead to 25-35 kB (observed in Q05, Q06, Q07, Q11, Q15, Q18).
- **`quicksort`**: Employed when the entire sorted result must be returned without a restrictive `LIMIT` clause (e.g. Q09, Q13, Q17, Q21), running entirely in memory within the 4 MB `work_mem` limit.

---

## 7. Indexing Optimization Experiments (Before vs After)

In accordance with DBMS project requirements, we evaluated whether additional indexes are justified. An index must not be added blindly; each proposed index must address a concrete access path inefficiency and demonstrate a measurable performance gain while considering write overhead.

We executed **4 controlled experiments** comparing execution plans before and after creating proposed indexes. After collecting benchmark evidence, proposed indexes were dropped to preserve the pristine schema.

### Index Experiment Summary Table

| Experiment | Target Query & Access Need | Baseline Plan | Proposed Index DDL | Optimized Plan | Speedup | Execution Plan Files |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **EXP1_podcasts_status_created_at** | Index on podcasts(status, created_at DESC) for podcast browsing feed | 0.148 ms (Cost: 35.76) | `CREATE INDEX idx_podcasts_status_created_at ON podcasts (status, created_at DESC);` | 0.019 ms (Cost: 1.83) | **7.79x** | [`Before`](plans/opt01_browse_podcasts_before_idx.txt) / [`After`](plans/opt01_browse_podcasts_after_idx.txt) |
| **EXP2_courses_status_created_at** | Index on courses(status, created_at DESC) for course marketplace catalog | 0.083 ms (Cost: 16.01) | `CREATE INDEX idx_courses_status_created_at ON courses (status, created_at DESC);` | 0.019 ms (Cost: 2.23) | **4.37x** | [`Before`](plans/opt02_browse_courses_before_idx.txt) / [`After`](plans/opt02_browse_courses_after_idx.txt) |
| **EXP3_rentals_renter_created_at** | Composite index on rentals(renter_id, created_at DESC) for user rental history | 0.030 ms (Cost: 10.99) | `CREATE INDEX idx_rentals_renter_created_at ON rentals (renter_id, created_at DESC);` | 0.032 ms (Cost: 10.99) | **0.94x** | [`Before`](plans/opt03_rental_history_before_idx.txt) / [`After`](plans/opt03_rental_history_after_idx.txt) |
| **EXP4_reviews_course_created_at** | Partial composite index on reviews(course_id, created_at DESC) for target reviews chronological feed | 0.040 ms (Cost: 17.80) | `CREATE INDEX idx_reviews_course_created_at ON reviews (course_id, created_at DESC) WHERE course_id IS NOT NULL;` | 0.042 ms (Cost: 17.80) | **0.95x** | [`Before`](plans/opt04_course_reviews_before_idx.txt) / [`After`](plans/opt04_course_reviews_after_idx.txt) |

### Detailed Experiment Walkthrough

#### Experiment 1: Feed Ordering on `podcasts (status, created_at DESC)`
- **Problem:** The active podcast discovery feed (`WHERE status = 'active' ORDER BY created_at DESC LIMIT 10`) required a full `Seq Scan` on `podcasts` (cost 35.74..35.76) followed by an explicit `top-N heapsort`.
- **Solution:** Created composite B-Tree index: `CREATE INDEX idx_podcasts_status_created_at ON podcasts (status, created_at DESC);`
- **Plan Impact:** The optimizer switched from `Seq Scan + Sort` to a direct `Index Scan using idx_podcasts_status_created_at`. The Sort node was completely eliminated because index leaf pages are already ordered chronologically. Planner cost dropped by **94.9%** (from 35.76 to 1.83), execution buffers dropped from 20 to 4 pages (**80.0% reduction**), and execution time accelerated by **7.79x** (from 0.148 ms to 0.019 ms).
- **Recommendation:** **Strongly Recommended** for production adoption.

#### Experiment 2: Marketplace Catalog on `courses (status, created_at DESC)`
- **Problem:** Browsing published courses ordered chronologically triggered a `Seq Scan` on `courses` followed by in-memory sorting.
- **Solution:** Created composite B-Tree index: `CREATE INDEX idx_courses_status_created_at ON courses (status, created_at DESC);`
- **Plan Impact:** Replaced the sequential table scan and sort with a direct `Index Scan`. Estimated cost dropped from 16.01 to 2.23 (**86.1% reduction**), execution buffers decreased from 11 to 4 pages (**63.6% reduction**), and execution time decreased from 0.083 ms to 0.019 ms (**4.37x speedup**).
- **Recommendation:** **Recommended** as course catalog traffic scales.

#### Experiment 3: Composite Index on `rentals (renter_id, created_at DESC)`
- **Problem:** `rentals` already possesses `ix_rentals_renter_id`. When querying rental history for a user sorted by `created_at DESC`, the baseline plan performs a `Bitmap Heap Scan` using `ix_rentals_renter_id` and sorts the matching rows via `quicksort`.
- **Solution:** Tested composite index: `CREATE INDEX idx_rentals_renter_created_at ON rentals (renter_id, created_at DESC);`
- **Plan Impact:** The optimizer continued using a Bitmap Heap Scan + quicksort because the number of rentals per user is very small (1-5 rows). The in-memory quicksort took only 0.008 ms. The composite index produced identical cost (10.99), identical execution buffers (9 hits), and effectively identical runtime (0.030 ms vs 0.032 ms).
- **Recommendation:** **Not Justified.** The existing single-column index `ix_rentals_renter_id` is sufficient. Adding a composite index would add write amplification without measurable read benefit.

#### Experiment 4: Redundant Composite Partial Index on `reviews (course_id, created_at DESC)`
- **Problem:** Retrieving reviews for an entity ordered chronologically uses partial unique index `uq_reviews_course_target_reviewer` to filter by `course_id`, then sorts the reviews in memory.
- **Solution:** Tested adding a partial ordering index: `CREATE INDEX idx_reviews_course_created_at ON reviews (course_id, created_at DESC) WHERE course_id IS NOT NULL;`
- **Plan Impact:** Because the number of reviews per course is small (4-20 rows), sorting 4 rows in memory took 0.009 ms. Planner cost remained unchanged at 17.80, execution buffers remained identical at 12 hits, and execution time remained effectively identical (0.040 ms vs 0.042 ms).
- **Recommendation:** **Not Justified.** The schema's existing partial unique index already filters the target effectively.

---

## 8. Identification of Expensive Queries and Query Rewrite Optimization

### Expensive Query Ranking
From our profiling workload, the queries requiring the highest computational effort were:
1. **`Q07` (Browse Published Courses with Lessons & Reviews):** `7.389 ms` | Cost: `2782.49` | Exec Buffers: `4554` hits
2. **`Q26` (Course Curriculum Funnel & Completion Rate):** `2.055 ms` | Cost: `378.10` | Exec Buffers: `112` hits
3. **`Q05` (Browse & Search Active Podcasts):** `1.145 ms` | Cost: `402.70` | Exec Buffers: `426` hits

### Architectural Diagnosis: The Cartesian Product Fan-Out Problem in Q07
Query `Q07` represents a classic database design pitfall known as the **Chasm Trap / Cartesian Fan-Out**. The query joins `courses` to two independent one-to-many child tables in a single flat join:
```sql
-- Problematic Flat Join Structure in Q07:
FROM courses c
LEFT JOIN lessons l ON c.course_id = l.course_id
LEFT JOIN reviews r ON c.course_id = r.course_id
```
If a course has 10 lessons and 4 reviews, the flat join produces **40 intermediate joined rows** for that single course! Across 100 candidate courses, the executor must process **4,000 joined tuples**.

To prevent inflated numbers, the query is forced to compute distinct aggregates:
`COUNT(DISTINCT l.lesson_id)` and `COUNT(DISTINCT r.review_id)`.
This forces PostgreSQL into expensive `Incremental Sort` and `GroupAggregate` routines, consuming **4,554 execution buffer hits** and **7.389 ms**.

### Query Rewrite Optimization: Subquery Pre-Aggregation
Rather than flattening independent one-to-many relationships, the query should **pre-aggregate each child relation independently in subqueries (or CTEs) before joining** to the parent `courses` table:

```sql
-- Optimized Subquery Pre-Aggregation Rewrite:
SELECT
    c.course_id,
    c.instructor_id,
    c.title,
    c.description,
    c.price,
    c.currency,
    c.created_at,
    pr.display_name AS instructor_name,
    pr.avatar_url AS instructor_avatar,
    COALESCE(l_stats.total_lessons, 0) AS total_lessons,
    COALESCE(l_stats.total_duration_seconds, 0) AS total_duration_seconds,
    COALESCE(r_stats.average_rating, 0) AS average_rating,
    COALESCE(r_stats.review_count, 0) AS review_count
FROM courses c
JOIN users u ON c.instructor_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN (
    SELECT course_id, COUNT(lesson_id) AS total_lessons, SUM(duration_seconds) AS total_duration_seconds
    FROM lessons GROUP BY course_id
) l_stats ON c.course_id = l_stats.course_id
LEFT JOIN (
    SELECT course_id, ROUND(AVG(rating), 2) AS average_rating, COUNT(review_id) AS review_count
    FROM reviews WHERE course_id IS NOT NULL GROUP BY course_id
) r_stats ON c.course_id = r_stats.course_id
WHERE c.status = 'published'
  AND (100.00::NUMERIC IS NULL OR c.price <= 100.00)
ORDER BY c.created_at DESC
LIMIT 10 OFFSET 0;
```

### Empirical Performance Comparison: Q07 Baseline vs Pre-Aggregated Rewrite

| Metric | Baseline Q07 (Flat Join) | Optimized Q07 (Pre-Aggregated) | Measurable Improvement |
| :--- | :---: | :---: | :---: |
| **Optimizer Estimated Cost** | `2782.49` | `316.84` | **88.6% cost reduction** |
| **Execution Time** | `7.389 ms` | `3.133 ms` | **2.36x faster** |
| **Execution Shared Buffer Hits** | `4554 pages` | `160 pages` | **96.5% buffer reduction** |
| **Planning Time** | `1.983 ms` | `4.255 ms` | Expected slight planning overhead |
| **Intermediate Rows Processed** | `4,000 Cartesian tuples` | `100 1-to-1 joined rows` | **97.5% reduction in tuples** |
| **Aggregate Operator** | `GroupAggregate (COUNT DISTINCT)` | `HashAggregate` on small group | Eliminates distinct sorting |
| **Archived Execution Plan** | [`q07_browse_published_courses.txt`](plans/q07_browse_published_courses.txt) | [`opt05_course_browse_preaggregate_rewrite.txt`](plans/opt05_course_browse_preaggregate_rewrite.txt) | Documented plan evidence |

---

## 9. Observations and Optimization Opportunities

Based on our empirical analysis of the PostgreSQL query planner, we summarize key findings and actionable recommendations for PodSphere:

1. **Index Coverage in Baseline Schema:** The existing schema (`03_schema.sql`) provides strong baseline index coverage. Primary keys, unique constraints, and foreign key indexes ensure that almost all entity-by-ID and point lookups execute in under **0.2 ms**.
2. **Compound Filtering & Sorting Opportunity:** Public feeds with filtering and sorting (such as active podcasts and published courses) benefit significantly from composite indexes on `(status, created_at DESC)`. In our tests, this eliminated sequential scans and sorting, delivering up to **7.79x speedup** on podcasts and **4.37x speedup** on courses.
3. **Avoid Over-Indexing Low-Cardinality Relationships:** For one-to-many relationships where an entity has very few child rows (e.g. rentals per renter or reviews per course), compound sorting indexes provide no measurable benefit over existing foreign key indexes, while burdening write transactions.
4. **Pre-Aggregation Over Cartesian Joins:** Multi-table reporting queries that combine multiple one-to-many children must use subquery pre-aggregation. This reduces buffer hits by over 96% and prevents exponential tuple expansion.
5. **Leverage GiST Range Types for Reservations:** The `tstzrange` GiST exclusion constraint on `studio_bookings` and the `daterange` logic on `rentals` provide exceptional concurrency protection and sub-millisecond slot availability verification.

---

## 10. Conclusion

The Checkpoint 4 query timing and performance evaluation for PodSphere is complete:

- **Authentic Database Profiling:** All measurements reflect genuine PostgreSQL 18.7 execution plans run against a populated 61,125-row relational database.
- **Complete Workload Coverage:** Evaluated 28 representative queries across Authentication, Profiles, Roles, Podcasts, Episodes, Courses, Lessons, Enrollments, Progress, Equipment, Rentals, Studios, Bookings, Services, Orders, Payments, Transactions, Payouts, Reviews, Creator Plans, and Analytics.
- **Documented Query Plans:** Every plan is archived as a formatted, readable `.txt` file inside `dbms/plans/` (37 plans total: 28 representative query plans, 8 before/after indexing plans, and 1 query rewrite optimization plan).
- **Empirical Indexing Insights:** Demonstrated both successful index accelerations (7.79x speedup on podcast browsing) and justified index rejections (avoiding unnecessary compound indexes on low-cardinality foreign keys).
- **Precise Metrics Reconciliation:** All reported planning times, execution times, estimated costs, actual time ranges, row counts, execution buffers, and planning buffers strictly correspond to the saved plan artifacts.
- **Schema Integrity Preserved:** The pristine CP2 schema and CP3 queries remain unmodified, with optimizations thoroughly documented for production consideration.

This concludes the database engineering deliverables for PodSphere CP1 through CP4.
