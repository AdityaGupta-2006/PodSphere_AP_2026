# CP1: Database Normalization for PodSphere

## 1. Title and project information

- **Project:** PodSphere - Podcast Creator Ecosystem
- **Deliverable:** CP1 database normalization
- **Target database:** PostgreSQL

## 2. Introduction

This document develops a normalized logical data model for PodSphere from the supplied project requirements. It records assumptions, candidate keys, foreign keys, functional dependencies, a worked UNF-to-3NF decomposition, and the final relation set. It is a design proposal, not a description of deployed software.

## 3. Application overview and scope

PodSphere is planned to support creators through learning, planning, equipment discovery and rental, studio booking, service hiring, podcast production, publishing, growth, and monetization. The proposed relations cover identity and roles, podcasts and episodes, learning, marketplace listings and orders, financial records, reviews, and creator plans and tasks.

The finance relations cover payment records, their transaction events, and provider payouts only. Sponsorship agreements, subscriptions, premium-content entitlements, affiliate offers, and commission rules are not modeled because their product rules and attributes are not specified. They remain future scope; their existence is not implied by the generic finance tables. Dashboard metrics are derived from normalized records rather than stored as competing source-of-truth values. AI recommendation history is also outside this model until retention and provenance requirements are defined.

## 4. Database requirements and assumptions

PodSphere is a planned podcast-creator platform. This document proposes a logical relational model for its stated identity, podcast, learning, marketplace, booking, finance, feedback, and creator-planning requirements. It describes a design, not features already implemented in the repository. No migrations or application models were present at the time this document was prepared.

The model targets PostgreSQL. Identifiers use `BIGINT GENERATED ALWAYS AS IDENTITY`; timestamps use `TIMESTAMPTZ`; prices use `NUMERIC(12,2)` and ISO 4217 currency codes use `CHAR(3)`. Monetary values are non-negative amounts in the stated currency, unless a future ledger design explicitly adopts signed entries. `created_at` fields are required and default to the insertion time. Status values are constrained to documented application vocabularies, preferably with `CHECK` constraints or lookup tables if they become administrable data.

`Users` represents accounts. Provider, instructor, creator, and administrator are roles assigned through `User_Roles`, not mutually exclusive account types. In references such as `provider_id`, the referenced user is expected to hold the provider role; that cross-table role rule must be enforced by application logic or an appropriate database trigger. `Profiles` holds common public-facing profile information; role-specific profile extensions can be added if actual requirements need distinct attributes.

This model avoids storing derived dashboard totals, average ratings, course completion rates, rental totals, or payout balances as authoritative duplicate values. They can be calculated from source rows or maintained later as explicitly rebuildable caches/materialized views. A podcast category is represented as a value on `Podcasts` because no category catalog was specified. Payment-to-purchase allocation and payout-to-transaction allocation are also not specified as entities here; their addition should be considered when reconciliation requirements are defined.

### Notation

- `PK`: primary key; `FK`: foreign key; `UQ`: unique constraint or candidate key.
- `NN`: `NOT NULL`; `NULL`: nullable by design.
- Unless otherwise stated, identifiers are `BIGINT`, text is `TEXT` or bounded `VARCHAR`, booleans are `BOOLEAN`, and instants are `TIMESTAMPTZ`.
- A candidate key is a minimal set of attributes that uniquely identifies a tuple. The chosen primary key is one candidate key; listed alternate keys are additional candidate keys.
- Foreign keys should normally use `ON DELETE RESTRICT` for financial/history-bearing records. Account deletion should generally be handled by deactivation or an explicit retention/anonymization policy rather than cascading through business records.

## 5. Entity identification and attributes

Each row below gives `attribute (type; nullability; key role): meaning`. Attributes not marked nullable are required. Primary and foreign keys are identified explicitly. `created_at` defaults to the insertion time unless noted.

### Identity

#### Users

| Attribute | Definition |
| --- | --- |
| `user_id` | `BIGINT; NN; PK`: account identifier. |
| `email` | `VARCHAR(320); NN; UQ`: canonical sign-in/contact email; store normalized lowercase form. Enforce uniqueness on `lower(email)` if canonical storage cannot be guaranteed. |
| `password_hash` | `TEXT; NN`: password verifier, never a plaintext password. |
| `created_at` | `TIMESTAMPTZ; NN`: account creation instant. |
| `account_status` | `VARCHAR(20); NN`: account lifecycle state, for example pending, active, suspended, or closed. |

Candidate keys: `{user_id}`, `{email}`. `email` is unique; a PostgreSQL expression unique index on `lower(email)` is an alternative when case-insensitive uniqueness is required.

#### Roles

| Attribute | Definition |
| --- | --- |
| `role_id` | `BIGINT; NN; PK`: role identifier. |
| `role_name` | `VARCHAR(40); NN; UQ`: stable role name, such as creator, provider, instructor, or administrator. |
| `description` | `TEXT; NULL`: human-readable role description. |

Candidate keys: `{role_id}`, `{role_name}`.

#### User_Roles

| Attribute | Definition |
| --- | --- |
| `user_id` | `BIGINT; NN; PK, FK -> Users.user_id`: account receiving the role. |
| `role_id` | `BIGINT; NN; PK, FK -> Roles.role_id`: assigned role. |
| `assigned_at` | `TIMESTAMPTZ; NN`: assignment instant. |

Candidate key: `{user_id, role_id}`. The composite primary key prevents duplicate assignment; no surrogate identifier is needed.

#### Profiles

| Attribute | Definition |
| --- | --- |
| `profile_id` | `BIGINT; NN; PK`: profile identifier. |
| `user_id` | `BIGINT; NN; FK -> Users.user_id; UQ`: account owning this common profile; at most one common profile per user. |
| `display_name` | `VARCHAR(120); NN`: public display name. |
| `bio` | `TEXT; NULL`: profile biography. |
| `avatar_url` | `TEXT; NULL`: profile image URL. |
| `website_url` | `TEXT; NULL`: optional external website. |
| `updated_at` | `TIMESTAMPTZ; NN`: most recent profile update. |

Candidate keys: `{profile_id}`, `{user_id}`. A profile need not exist for every account, hence the one-to-one relationship is optional from `Users` to `Profiles`.

### Podcast

#### Podcasts

| Attribute | Definition |
| --- | --- |
| `podcast_id` | `BIGINT; NN; PK`: podcast identifier. |
| `creator_id` | `BIGINT; NN; FK -> Users.user_id`: owning creator account. |
| `title` | `VARCHAR(200); NN`: podcast title. |
| `description` | `TEXT; NULL`: podcast description. |
| `category` | `VARCHAR(100); NULL`: category label; promote to a category relation only if a managed shared vocabulary is required. |
| `language` | `VARCHAR(35); NULL`: language tag, preferably BCP 47. |
| `status` | `VARCHAR(20); NN`: draft, active, archived, or another defined lifecycle state. |
| `created_at` | `TIMESTAMPTZ; NN`: creation instant. |

Candidate key: `{podcast_id}`. No title uniqueness is assumed; a creator may use similar titles and titles may be reused by different creators.

#### Episodes

| Attribute | Definition |
| --- | --- |
| `episode_id` | `BIGINT; NN; PK`: episode identifier. |
| `podcast_id` | `BIGINT; NN; FK -> Podcasts.podcast_id`: parent podcast. |
| `episode_number` | `INTEGER; NN`: episode order/number within its podcast. |
| `title` | `VARCHAR(200); NN`: episode title. |
| `description` | `TEXT; NULL`: episode description. |
| `media_url` | `TEXT; NULL`: media location; nullable while a draft is not uploaded. |
| `duration_seconds` | `INTEGER; NULL`: known duration in seconds; non-negative when present. |
| `status` | `VARCHAR(20); NN`: draft, scheduled, published, or another defined state. |
| `published_at` | `TIMESTAMPTZ; NULL`: publication instant; null before publication. |

Candidate keys: `{episode_id}`, `{podcast_id, episode_number}`. Enforce `UNIQUE (podcast_id, episode_number)` and a positive episode number.

### Learning

#### Courses

| Attribute | Definition |
| --- | --- |
| `course_id` | `BIGINT; NN; PK`: course identifier. |
| `instructor_id` | `BIGINT; NN; FK -> Users.user_id`: instructor account. |
| `title` | `VARCHAR(200); NN`: course title. |
| `description` | `TEXT; NULL`: course description. |
| `price` | `NUMERIC(12,2); NN`: current listed price; non-negative. |
| `currency` | `CHAR(3); NN`: ISO 4217 currency for the listed price. |
| `status` | `VARCHAR(20); NN`: draft, published, or another defined state. |
| `created_at` | `TIMESTAMPTZ; NN`: course creation instant. |

Candidate key: `{course_id}`. Instructor status is a role rule, not encoded as a duplicated instructor attribute.

#### Lessons

| Attribute | Definition |
| --- | --- |
| `lesson_id` | `BIGINT; NN; PK`: lesson identifier. |
| `course_id` | `BIGINT; NN; FK -> Courses.course_id`: containing course. |
| `lesson_order` | `INTEGER; NN`: position within the course. |
| `title` | `VARCHAR(200); NN`: lesson title. |
| `content_url` | `TEXT; NULL`: lesson content location; nullable for a draft lesson. |
| `duration_seconds` | `INTEGER; NULL`: estimated or known duration in seconds. |

Candidate keys: `{lesson_id}`, `{course_id, lesson_order}`. Enforce unique lesson order within a course and positive ordering.

#### Enrollments

| Attribute | Definition |
| --- | --- |
| `enrollment_id` | `BIGINT; NN; PK`: enrollment identifier. |
| `user_id` | `BIGINT; NN; FK -> Users.user_id`: enrolled learner. |
| `course_id` | `BIGINT; NN; FK -> Courses.course_id`: enrolled course. |
| `enrolled_at` | `TIMESTAMPTZ; NN`: enrollment instant. |
| `status` | `VARCHAR(20); NN`: active, completed, withdrawn, or another defined state. |

Candidate keys: `{enrollment_id}`, `{user_id, course_id}`. Enforce `UNIQUE (user_id, course_id)` so a user has one enrollment record per course; re-enrollment policy should update/reopen that record or be modeled explicitly if history is required.

#### Lesson_Progress

| Attribute | Definition |
| --- | --- |
| `user_id` | `BIGINT; NN; PK, FK -> Users.user_id`: learner. |
| `lesson_id` | `BIGINT; NN; PK, FK -> Lessons.lesson_id`: lesson whose progress is recorded. |
| `is_completed` | `BOOLEAN; NN; DEFAULT FALSE`: completion state. |
| `completed_at` | `TIMESTAMPTZ; NULL`: completion instant; null until completed. |
| `updated_at` | `TIMESTAMPTZ; NN`: last progress update. |

Candidate key: `{user_id, lesson_id}`. Check that `completed_at` is null when `is_completed` is false and non-null when true, if completion is represented as a single terminal state. The user must be enrolled in the course containing the lesson; enforcing that cross-relation condition requires application logic or a trigger. Course ID is deliberately not copied here because it is determined by `lesson_id` and would be redundant.

### Equipment marketplace

#### Equipment_Categories
| Attribute | Definition |
| --- | --- |
| `category_id` | `BIGINT; NN; PK`: equipment category identifier. |
| `category_name` | `VARCHAR(100); NN; UQ`: category name. |
| `description` | `TEXT; NULL`: category description. |

Candidate keys: `{category_id}`, `{category_name}`.

#### Equipment

| Attribute | Definition |
| --- | --- |
| `equipment_id` | `BIGINT; NN; PK`: listing identifier. |
| `provider_id` | `BIGINT; NN; FK -> Users.user_id`: listing owner/provider. |
| `category_id` | `BIGINT; NN; FK -> Equipment_Categories.category_id`: category. |
| `equipment_name` | `VARCHAR(200); NN`: listing name. |
| `description` | `TEXT; NULL`: item details. |
| `daily_rate` | `NUMERIC(12,2); NN`: current listed daily rate; non-negative. |
| `currency` | `CHAR(3); NN`: ISO 4217 currency for the daily rate. |
| `quantity` | `INTEGER; NN`: listed inventory quantity; positive. |
| `equipment_status` | `VARCHAR(20); NN`: available, unavailable, or another defined state. |

Candidate key: `{equipment_id}`. Listing price describes the current offer only; historical rental prices belong to `Rentals`.

#### Rentals

| Attribute | Definition |
| --- | --- |
| `rental_id` | `BIGINT; NN; PK`: rental identifier. |
| `equipment_id` | `BIGINT; NN; FK -> Equipment.equipment_id`: rented listing. |
| `renter_id` | `BIGINT; NN; FK -> Users.user_id`: renting account. |
| `start_date` | `DATE; NN`: first rental date. |
| `end_date` | `DATE; NN`: final rental date under the product's inclusive/exclusive date policy. |
| `quantity` | `INTEGER; NN`: units agreed for this rental; positive. |
| `agreed_rate` | `NUMERIC(12,2); NN`: agreed per-unit daily rate captured when this rental was accepted; non-negative. |
| `currency` | `CHAR(3); NN`: currency of the agreed rate, captured with the rate. |
| `status` | `VARCHAR(20); NN`: requested, confirmed, active, completed, cancelled, or another defined state. |
| `created_at` | `TIMESTAMPTZ; NN`: rental record creation instant. |

Candidate key: `{rental_id}`. Check `end_date > start_date`. The agreed rate and currency are snapshots and must not be updated merely because the equipment listing changes. Rental totals are derivable from duration, quantity, and rate under the agreed date/proration policy; do not store a second authoritative total without a specific accounting requirement. Inventory availability across overlapping rentals requires a concurrency-aware database/application rule.

### Studios and services

#### Studios

| Attribute | Definition |
| --- | --- |
| `studio_id` | `BIGINT; NN; PK`: studio listing identifier. |
| `provider_id` | `BIGINT; NN; FK -> Users.user_id`: studio provider. |
| `studio_name` | `VARCHAR(200); NN`: studio name. |
| `location` | `TEXT; NN`: address or location description. |
| `capacity` | `INTEGER; NN`: maximum intended occupancy; positive. |
| `hourly_rate` | `NUMERIC(12,2); NN`: current listed hourly price; non-negative. |
| `currency` | `CHAR(3); NN`: ISO 4217 currency for the hourly rate. |
| `status` | `VARCHAR(20); NN`: available, unavailable, or another defined state. |

Candidate key: `{studio_id}`. No global name uniqueness is assumed.

#### Studio_Bookings

| Attribute | Definition |
| --- | --- |
| `booking_id` | `BIGINT; NN; PK`: booking identifier. |
| `studio_id` | `BIGINT; NN; FK -> Studios.studio_id`: booked studio. |
| `customer_id` | `BIGINT; NN; FK -> Users.user_id`: booking customer. |
| `start_time` | `TIMESTAMPTZ; NN`: beginning of the booked period. |
| `end_time` | `TIMESTAMPTZ; NN`: end of the booked period. |
| `agreed_rate` | `NUMERIC(12,2); NN`: agreed hourly rate captured at booking; non-negative. |
| `currency` | `CHAR(3); NN`: currency of the captured rate. |
| `status` | `VARCHAR(20); NN`: requested, confirmed, completed, cancelled, or another defined state. |
| `created_at` | `TIMESTAMPTZ; NN`: booking creation instant. |

Candidate key: `{booking_id}`. Check `end_time > start_time`. The agreed rate is a historical snapshot, not a reference to the current studio rate. Prevent overlapping confirmed bookings for a studio using a concurrency-safe rule; a PostgreSQL exclusion constraint over a time range is an option, but timestamp equality in a GiST constraint may require the `btree_gist` extension. The extension is not assumed to be installed.

#### Services

| Attribute | Definition |
| --- | --- |
| `service_id` | `BIGINT; NN; PK`: service listing identifier. |
| `provider_id` | `BIGINT; NN; FK -> Users.user_id`: service provider. |
| `service_name` | `VARCHAR(200); NN`: service name. |
| `description` | `TEXT; NULL`: service scope/details. |
| `price` | `NUMERIC(12,2); NN`: current listed price; non-negative. |
| `currency` | `CHAR(3); NN`: ISO 4217 currency for the listed price. |
| `status` | `VARCHAR(20); NN`: active, inactive, or another defined state. |

Candidate key: `{service_id}`. A provider may list multiple services; service names are not assumed unique across providers.

#### Service_Orders

| Attribute | Definition |
| --- | --- |
| `service_order_id` | `BIGINT; NN; PK`: service order identifier. |
| `service_id` | `BIGINT; NN; FK -> Services.service_id`: ordered service listing. |
| `customer_id` | `BIGINT; NN; FK -> Users.user_id`: customer account. |
| `agreed_price` | `NUMERIC(12,2); NN`: price agreed for this order, captured at acceptance; non-negative. |
| `currency` | `CHAR(3); NN`: currency of the agreed price. |
| `requirements` | `TEXT; NULL`: customer-supplied scope, deliverables, or instructions. |
| `scheduled_at` | `TIMESTAMPTZ; NULL`: agreed service appointment or start time, when the service is scheduled. |
| `status` | `VARCHAR(20); NN`: requested, accepted, in_progress, completed, cancelled, or another defined state. |
| `created_at` | `TIMESTAMPTZ; NN`: order creation instant. |
| `completed_at` | `TIMESTAMPTZ; NULL`: completion instant; null until the order is completed. |

Candidate key: `{service_order_id}`. The agreed price is a snapshot; it must not be derived from the mutable `Services.price` after order creation. `requirements`, `scheduled_at`, and `completed_at` may be null when not supplied, not scheduled, or not completed.

### Finance and feedback

#### Payments

| Attribute | Definition |
| --- | --- |
| `payment_id` | `BIGINT; NN; PK`: payment identifier. |
| `payer_id` | `BIGINT; NN; FK -> Users.user_id`: account making the payment. |
| `amount` | `NUMERIC(12,2); NN`: requested/accepted payment amount; non-negative. |
| `currency` | `CHAR(3); NN`: ISO 4217 currency for the amount. |
| `payment_method` | `VARCHAR(40); NN`: method/category identifier; do not store raw card or bank credentials here. |
| `payment_status` | `VARCHAR(20); NN`: pending, authorized, paid, failed, refunded, or another defined lifecycle state. |
| `payment_reference` | `VARCHAR(200); NULL; UQ`: external payment-provider reference when assigned; unique when non-null. |
| `created_at` | `TIMESTAMPTZ; NN`: payment creation instant. |
| `paid_at` | `TIMESTAMPTZ; NULL`: successful payment instant; null until paid. |

Candidate key: `{payment_id}`. Enforce uniqueness for each non-null `payment_reference` with a unique constraint/index; because the attribute is nullable, it is not a candidate key for the whole relation. `paid_at` is nullable for payments not completed. The business object funded by a payment is intentionally not guessed; add explicit order/payment allocation relations when that requirement is settled.

#### Transactions

| Attribute | Definition |
| --- | --- |
| `transaction_id` | `BIGINT; NN; PK`: financial transaction/event identifier. |
| `payment_id` | `BIGINT; NN; FK -> Payments.payment_id`: payment to which the event belongs. |
| `transaction_type` | `VARCHAR(30); NN`: event type, for example authorization, capture, refund, or fee. |
| `amount` | `NUMERIC(12,2); NN`: amount for this event; non-negative, with event type indicating its meaning. |
| `transaction_status` | `VARCHAR(20); NN`: pending, succeeded, failed, or another defined state. |
| `provider_reference` | `VARCHAR(200); NULL; UQ`: external transaction reference when supplied; unique when non-null. |
| `created_at` | `TIMESTAMPTZ; NN`: event record creation instant. |

Candidate key: `{transaction_id}`. Enforce uniqueness for each non-null `provider_reference` with a unique constraint/index; because it is nullable, it is not a candidate key for the whole relation. A payment may have multiple transaction events. This relation is not collapsed into `Payments`: one payment may have multiple attempts, captures, refunds, or other events. Currency can be obtained from the referenced payment and is not duplicated here; if a processor supports event currency conversion, model the conversion explicitly rather than silently copying a potentially different currency.

#### Payouts

| Attribute | Definition |
| --- | --- |
| `payout_id` | `BIGINT; NN; PK`: provider payout identifier. |
| `provider_id` | `BIGINT; NN; FK -> Users.user_id`: recipient provider account. |
| `amount` | `NUMERIC(12,2); NN`: payout amount; non-negative. |
| `currency` | `CHAR(3); NN`: ISO 4217 currency for the payout. |
| `status` | `VARCHAR(20); NN`: pending, processing, paid, failed, or another defined state. |
| `payout_reference` | `VARCHAR(200); NULL; UQ`: external payout reference when assigned; unique when non-null. |
| `created_at` | `TIMESTAMPTZ; NN`: payout creation instant. |
| `paid_at` | `TIMESTAMPTZ; NULL`: successful transfer instant; null until paid. |

Candidate key: `{payout_id}`. Enforce uniqueness for each non-null `payout_reference`; its nullability means it is not a candidate key for the whole relation. Payouts are distinct from customer payments. Source transaction allocation, commission calculation, and reconciliation are intentionally not inferred; add a payout allocation relation if payouts must be traced to individual transactions.

#### Reviews

| Attribute | Definition |
| --- | --- |
| `review_id` | `BIGINT; NN; PK`: review identifier. |
| `reviewer_id` | `BIGINT; NN; FK -> Users.user_id`: account authoring the review. |
| `reviewed_user_id` | `BIGINT; NULL; FK -> Users.user_id`: provider/instructor account being reviewed, when the target is a person. |
| `equipment_id` | `BIGINT; NULL; FK -> Equipment.equipment_id`: equipment listing being reviewed, when targeted. |
| `studio_id` | `BIGINT; NULL; FK -> Studios.studio_id`: studio listing being reviewed, when targeted. |
| `service_id` | `BIGINT; NULL; FK -> Services.service_id`: service listing being reviewed, when targeted. |
| `course_id` | `BIGINT; NULL; FK -> Courses.course_id`: course being reviewed, when targeted. |
| `rating` | `SMALLINT; NN`: rating on the chosen scale, proposed as 1 through 5. |
| `review_text` | `TEXT; NULL`: optional written feedback. |
| `created_at` | `TIMESTAMPTZ; NN`: review creation instant. |

Candidate key: `{review_id}`. Exactly one of the five target foreign keys must be non-null; enforce with a `CHECK` constraint. Prevent duplicate reviews by the same reviewer for the same target with one partial unique index per target column. Whether a review requires a completed rental, booking, enrollment, or service order is a business rule not specified here and should be enforced once decided. This one-of-target design uses explicit foreign keys instead of an unchecked polymorphic target identifier.

### Creator planning

#### Creator_Plans

| Attribute | Definition |
| --- | --- |
| `plan_id` | `BIGINT; NN; PK`: creator plan identifier. |
| `creator_id` | `BIGINT; NN; FK -> Users.user_id`: plan owner. |
| `plan_title` | `VARCHAR(200); NN`: plan title. |
| `podcast_idea` | `TEXT; NULL`: idea or concept captured by the plan. |
| `target_launch_date` | `DATE; NULL`: intended launch date, if set. |
| `plan_status` | `VARCHAR(20); NN`: draft, active, completed, archived, or another defined state. |
| `created_at` | `TIMESTAMPTZ; NN`: plan creation instant. |
| `updated_at` | `TIMESTAMPTZ; NN`: most recent plan update. |

Candidate key: `{plan_id}`. Multiple plans per creator are allowed; no uniqueness on title is assumed.

#### Plan_Tasks

| Attribute | Definition |
| --- | --- |
| `task_id` | `BIGINT; NN; PK`: task identifier. |
| `plan_id` | `BIGINT; NN; FK -> Creator_Plans.plan_id`: parent plan. |
| `task_title` | `VARCHAR(200); NN`: actionable task title. |
| `task_category` | `VARCHAR(80); NULL`: optional task category. |
| `due_date` | `DATE; NULL`: optional target date. |
| `task_status` | `VARCHAR(20); NN`: not_started, in_progress, completed, or another defined state. |
| `task_order` | `INTEGER; NN`: display/order position within the plan. |
| `created_at` | `TIMESTAMPTZ; NN`: task creation instant. |

Candidate keys: `{task_id}`, `{plan_id, task_order}`. Enforce unique task ordering within a plan and positive order values.

## 6. Initial UNF relation

The following illustrative row shows a creator workflow stored as one record. Braces denote repeating groups, not literal values or a proposed PostgreSQL array column.

| creator_id | creator_name | podcast_id / title | episodes | course enrollments and lessons | rentals | studio bookings | service orders | payment details |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C01 | Anik | P01 / PodSphere Notes | `{(1, Launch), (2, Audio Setup)}` | `{(Course A, Lesson 1, complete), (Course B, Lesson 1, in progress)}` | `{(Mic M1, Nov 20-21), (Mixer M2, Nov 22-23)}` | `{(Studio S1, Nov 24 10:00-12:00)}` | `{(Service V1, editing), (Service V2, cover design)}` | `{(Payment Pay1, INR 2,000, paid, Transaction T1)}` |

This is UNF because episodes, enrollments/lessons, rentals, bookings, service orders, and payment events are multivalued groups in a single row. The row also repeats podcast and creator facts if copied once per child item. Such a layout obstructs constraints and updates: changing a podcast title requires editing many copies; a creator with no episode cannot be recorded cleanly; and deleting the last rental row could accidentally remove the only copy of rental-related information.

## 7. Functional dependencies

The following non-trivial functional dependencies (FDs) are assumed. Dependencies implied by primary keys are included even when they are the usual key-to-all-other-attributes dependency. Attributes omitted from an FD are not determined by its left-hand side unless another listed key/constraint establishes that fact.

| Relation | Functional dependencies |
| --- | --- |
| `Users` | `user_id -> email, password_hash, created_at, account_status`; `email -> user_id, password_hash, created_at, account_status`. |
| `Roles` | `role_id -> role_name, description`; `role_name -> role_id, description`. |
| `User_Roles` | `(user_id, role_id) -> assigned_at`. |
| `Profiles` | `profile_id -> user_id, display_name, bio, avatar_url, website_url, updated_at`; `user_id -> profile_id, display_name, bio, avatar_url, website_url, updated_at`. |
| `Podcasts` | `podcast_id -> creator_id, title, description, category, language, status, created_at`. |
| `Episodes` | `episode_id -> podcast_id, episode_number, title, description, media_url, duration_seconds, status, published_at`; `(podcast_id, episode_number) -> episode_id, title, description, media_url, duration_seconds, status, published_at`. |
| `Courses` | `course_id -> instructor_id, title, description, price, currency, status, created_at`. |
| `Lessons` | `lesson_id -> course_id, lesson_order, title, content_url, duration_seconds`; `(course_id, lesson_order) -> lesson_id, title, content_url, duration_seconds`. |
| `Enrollments` | `enrollment_id -> user_id, course_id, enrolled_at, status`; `(user_id, course_id) -> enrollment_id, enrolled_at, status`. |
| `Lesson_Progress` | `(user_id, lesson_id) -> is_completed, completed_at, updated_at`. |
| `Equipment_Categories` | `category_id -> category_name, description`; `category_name -> category_id, description`. |
| `Equipment` | `equipment_id -> provider_id, category_id, equipment_name, description, daily_rate, currency, quantity, equipment_status`. |
| `Rentals` | `rental_id -> equipment_id, renter_id, start_date, end_date, quantity, agreed_rate, currency, status, created_at`. |
| `Studios` | `studio_id -> provider_id, studio_name, location, capacity, hourly_rate, currency, status`. |
| `Studio_Bookings` | `booking_id -> studio_id, customer_id, start_time, end_time, agreed_rate, currency, status, created_at`. |
| `Services` | `service_id -> provider_id, service_name, description, price, currency, status`. |
| `Service_Orders` | `service_order_id -> service_id, customer_id, agreed_price, currency, requirements, scheduled_at, status, created_at, completed_at`. |
| `Payments` | `payment_id -> payer_id, amount, currency, payment_method, payment_status, payment_reference, created_at, paid_at`. |
| `Transactions` | `transaction_id -> payment_id, transaction_type, amount, transaction_status, provider_reference, created_at`. |
| `Payouts` | `payout_id -> provider_id, amount, currency, status, payout_reference, created_at, paid_at`. |
| `Reviews` | `review_id -> reviewer_id, reviewed_user_id, equipment_id, studio_id, service_id, course_id, rating, review_text, created_at`. |
| `Creator_Plans` | `plan_id -> creator_id, plan_title, podcast_idea, target_launch_date, plan_status, created_at, updated_at`. |
| `Plan_Tasks` | `task_id -> plan_id, task_title, task_category, due_date, task_status, task_order, created_at`; `(plan_id, task_order) -> task_id, task_title, task_category, due_date, task_status, created_at`. |

Nullable external references use partial uniqueness rules, not candidate keys or FDs over the entire relation. PostgreSQL unique constraints permit multiple nulls by default. Check constraints (such as exactly one review target) and temporal/inventory rules are domain constraints, not FDs.

## 8. Candidate keys and key analysis

The entity definitions in Section 5 identify each primary key and every assumed alternate candidate key. A declared `UNIQUE` constraint is justified only by a stated business rule: role names and category names are unique; a user's email is unique; episode numbers, lesson order, and task order are unique within their parent; and a user has at most one enrollment per course. Nullable gateway and payout references have partial unique indexes but are not candidate keys. No uniqueness is assumed for titles or provider listing names.

Surrogate primary keys do not erase alternate candidate keys. For example, `Episodes` uses `episode_id` as its primary key and `(podcast_id, episode_number)` as an alternate candidate key. Both determine the episode row under the stated uniqueness rule. `Enrollments` similarly has `{enrollment_id}` and `{user_id, course_id}`. In a relation with a composite candidate key, a partial dependency exists only when a non-prime attribute is determined by a proper subset of that key. A single-column candidate key cannot have such a partial dependency.

## 9. First Normal Form (1NF)

1NF requires one atomic value per attribute in each tuple and no repeating groups. The UNF row is expanded into child records rather than storing lists. For episodes, an atomic 1NF relation can be written as `CREATOR_EPISODE_1NF(creator_id, creator_name, podcast_id, podcast_title, episode_number, episode_title)`:

| creator_id | creator_name | podcast_id | podcast_title | episode_number | episode_title |
| --- | --- | --- | --- | --- | --- |
| C01 | Anik | P01 | PodSphere Notes | 1 | Launch |
| C01 | Anik | P01 | PodSphere Notes | 2 | Audio Setup |

The other repeating groups become atomic rows in their own relations: `Enrollments`, `Lesson_Progress`, `Rentals`, `Studio_Bookings`, `Service_Orders`, `Payments`, and `Transactions`. A workflow-wide Cartesian combination is not formed; independent child collections remain separate. 1NF removes repeating groups but does not by itself remove partial or transitive dependencies.

## 10. Second Normal Form (2NF)

For `CREATOR_EPISODE_1NF`, assume `podcast_id` identifies one podcast, episode numbers are unique within a podcast, and each podcast has one creator. Its candidate key is `{podcast_id, episode_number}`. The relevant FDs are:

- `podcast_id -> creator_id, podcast_title`
- `creator_id -> creator_name`
- `(podcast_id, episode_number) -> episode_title`
- Therefore `(podcast_id, episode_number) -> creator_id, creator_name, podcast_title, episode_title`.

`podcast_id -> creator_id, podcast_title` is a partial dependency: `podcast_id` is a proper subset of the composite candidate key, yet determines non-prime attributes. `episode_title` depends on the full key; under the assumptions above, neither podcast ID alone nor episode number alone identifies an episode. `creator_name` is also transitively determined through `podcast_id -> creator_id -> creator_name`.

2NF removes the partial dependency by decomposing the relation into:

| Relation | Attributes and key | Dependencies retained |
| --- | --- | --- |
| `PODCAST_2NF` | `(podcast_id PK, creator_id, creator_name, podcast_title)` | `podcast_id -> creator_id, creator_name, podcast_title`; `creator_id -> creator_name`. |
| `EPISODE_2NF` | `(podcast_id PK/FK, episode_number PK, episode_title)` | `(podcast_id, episode_number) -> episode_title`. |

The join on `podcast_id` is lossless because `podcast_id` is a key of `PODCAST_2NF`. Both relations are in 2NF. `PODCAST_2NF` has a single-attribute candidate key, so it cannot have a partial dependency; however, it still contains the transitive dependency through `creator_id`.

The same whole-key test applies in the final schema. In `Lesson_Progress`, `(user_id, lesson_id) -> is_completed, completed_at, updated_at`; neither component alone determines a learner's progress on every lesson. In `User_Roles`, `(user_id, role_id) -> assigned_at`. These are full dependencies, not partial dependencies. `Enrollments` has the alternate key `(user_id, course_id)`, which determines its enrollment facts as a whole. A single-column primary key such as `rental_id` does not violate 2NF merely because it is a single-column key.

## 11. Third Normal Form (3NF)

The formal 3NF condition is: for every non-trivial functional dependency `X -> A`, either `X` is a superkey or `A` is a prime attribute (an attribute that belongs to at least one candidate key).

In `PODCAST_2NF`, `creator_id -> creator_name` is non-trivial, `creator_id` is not a superkey, and `creator_name` is non-prime. It violates 3NF. Decompose it into:

| Relation | Attributes and key | Relevant dependency |
| --- | --- | --- |
| `CREATOR_3NF` | `(creator_id PK, creator_name)` | `creator_id -> creator_name`. |
| `PODCAST_3NF` | `(podcast_id PK, creator_id FK, podcast_title)` | `podcast_id -> creator_id, podcast_title`. |
| `EPISODE_3NF` | `(podcast_id PK/FK, episode_number PK, episode_title)` | `(podcast_id, episode_number) -> episode_title`. |

The decomposition is lossless: `creator_id` is a key of `CREATOR_3NF`, and `podcast_id` is a key of `PODCAST_3NF` when joined to episodes. Each listed determinant is a key in its relation, so the relations satisfy 3NF (and BCNF for these FDs). This example maps to the final design's `Users`/`Profiles`, `Podcasts`, and `Episodes`; the pedagogical `creator_name` is represented by the optional profile display name in the full model.

The same separation is applied throughout the schema: role descriptions are in `Roles`, equipment category details are in `Equipment_Categories`, provider/instructor accounts are referenced by listings and courses rather than copied, course details remain in `Courses` rather than `Lessons`, and plan details remain in `Creator_Plans` rather than `Plan_Tasks`. Historical agreed prices are separate transaction facts on rentals, bookings, and service orders, not transitive copies of mutable listing prices. Payments, transaction events, and payouts remain distinct relations. Derived dashboard measures are calculated from source rows.

## 12. Final normalized schema

The complete attributes and meanings are listed in Section 5. This compact index records each relation's primary key, foreign keys, and assumed alternate keys; it is not a second attribute inventory.

| Relation | Primary key | Foreign keys | Alternate candidate keys / unique rules |
| --- | --- | --- | --- |
| `Users` | `user_id` | - | `email` |
| `Roles` | `role_id` | - | `role_name` |
| `User_Roles` | `(user_id, role_id)` | `user_id -> Users`; `role_id -> Roles` | - |
| `Profiles` | `profile_id` | `user_id -> Users` | `user_id` |
| `Podcasts` | `podcast_id` | `creator_id -> Users` | - |
| `Episodes` | `episode_id` | `podcast_id -> Podcasts` | `(podcast_id, episode_number)` |
| `Courses` | `course_id` | `instructor_id -> Users` | - |
| `Lessons` | `lesson_id` | `course_id -> Courses` | `(course_id, lesson_order)` |
| `Enrollments` | `enrollment_id` | `user_id -> Users`; `course_id -> Courses` | `(user_id, course_id)` |
| `Lesson_Progress` | `(user_id, lesson_id)` | `user_id -> Users`; `lesson_id -> Lessons` | - |
| `Equipment_Categories` | `category_id` | - | `category_name` |
| `Equipment` | `equipment_id` | `provider_id -> Users`; `category_id -> Equipment_Categories` | - |
| `Rentals` | `rental_id` | `equipment_id -> Equipment`; `renter_id -> Users` | - |
| `Studios` | `studio_id` | `provider_id -> Users` | - |
| `Studio_Bookings` | `booking_id` | `studio_id -> Studios`; `customer_id -> Users` | - |
| `Services` | `service_id` | `provider_id -> Users` | - |
| `Service_Orders` | `service_order_id` | `service_id -> Services`; `customer_id -> Users` | - |
| `Payments` | `payment_id` | `payer_id -> Users` | partial unique `payment_reference` when non-null |
| `Transactions` | `transaction_id` | `payment_id -> Payments` | partial unique `provider_reference` when non-null |
| `Payouts` | `payout_id` | `provider_id -> Users` | partial unique `payout_reference` when non-null |
| `Reviews` | `review_id` | reviewer and one selected target FK | partial unique index per reviewer/target pair |
| `Creator_Plans` | `plan_id` | `creator_id -> Users` | - |
| `Plan_Tasks` | `task_id` | `plan_id -> Creator_Plans` | `(plan_id, task_order)` |

The review target is exactly one of `reviewed_user_id`, `equipment_id`, `studio_id`, `service_id`, and `course_id`; its nullable foreign keys all reference the relations named in Section 5.

## 13. Relationship and cardinality summary

- `Users` 1:N `Podcasts`; `Podcasts` 1:N `Episodes`.
- `Users` M:N `Roles` through `User_Roles`; `Users` 0..1:1 `Profiles`.
- `Users` M:N `Courses` through `Enrollments`; `Courses` 1:N `Lessons`.
- `Users` M:N `Lessons` through `Lesson_Progress`.
- `Users` 1:N `Equipment`; `Equipment_Categories` 1:N `Equipment`; `Equipment` 1:N `Rentals`, with each rental having one renter.
- `Users` 1:N `Studios`; `Studios` 1:N `Studio_Bookings`, with each booking having one customer.
- `Users` 1:N `Services`; `Services` 1:N `Service_Orders`, with each order having one customer.
- `Users` 1:N `Payments`; `Payments` 1:N `Transactions`; `Users` 1:N `Payouts` as provider recipient.
- `Users` 1:N `Creator_Plans`; `Creator_Plans` 1:N `Plan_Tasks`.
- Each review has one reviewer and exactly one supported target.

## 14. Integrity constraints and business rules

1. Enforce all listed foreign keys. A referenced provider or instructor is expected to hold the corresponding `User_Roles` assignment; that cross-table role rule needs application logic or a trigger.
2. Prevent duplicate course enrollment with `UNIQUE (user_id, course_id)`. Prevent duplicate lesson progress with the `Lesson_Progress` primary key `(user_id, lesson_id)`.
3. Prevent duplicate non-null payment gateway, transaction-provider, and payout references with unique constraints or partial unique indexes. These nullable references are not candidate keys.
4. Require valid positive amounts, rates, quantities, capacities, durations, ratings, order positions, and episode numbers. Require each rental or booking end to follow its start.
5. Prevent overlapping confirmed bookings for the same studio with a concurrency-safe exclusion constraint or equivalent transactional validation. An exclusion constraint on timestamp ranges may require PostgreSQL's `btree_gist` extension for studio equality.
6. Prevent overlapping equipment rentals from exceeding the listing's available quantity. This requires concurrency-safe transactional validation or a database constraint/trigger; an ordinary foreign key or FD does not enforce inventory availability.
7. Preserve the agreed rate and currency on rentals, bookings, and service orders. Later changes to listing prices must not rewrite historical agreements.
8. Define valid payment, refund, transaction, and payout state transitions. `CHECK` constraints can restrict status values but cannot enforce transition order by themselves. Refund authorization and payout reconciliation rules remain business decisions to specify before implementation.
9. Choose explicit deletion and retention policies. `RESTRICT` is the conservative default for financial/history-bearing rows; accounts should generally be deactivated or anonymized rather than cascaded away.
10. Do not store raw payment credentials. Commission calculation, tax, sponsorships, subscriptions, premium content, affiliate offers, and payment-to-order allocation need separate requirements and are outside this model.
11. Enforce exactly one review target and the target-specific uniqueness rule described in Section 5. Persist AI recommendations only if product requirements define history and provenance.

## 15. Normalization summary

The UNF example contains repeating groups; the 1NF conversion makes each child fact a separate atomic row. The worked episode relation exposes a partial dependency removed in 2NF and a transitive creator-name dependency removed in 3NF. The final relations have no intended partial or transitive dependencies under the documented keys and FDs, and satisfy 3NF. BCNF also holds under the stated FDs, but 3NF is the required design criterion.

## 16. Conclusion

The proposed PostgreSQL logical model covers the specified PodSphere CP1 entities and preserves the distinctions needed for roles, parent-child content, enrollments, progress, historical prices, payment events, payouts, reviews, and creator planning. The model is a normalization baseline for a planned application; it does not claim that the schema or future product modules have been implemented.

## 17. References

No external sources were used. The application scope and business assumptions are based on the project requirements supplied for this CP1 deliverable.
