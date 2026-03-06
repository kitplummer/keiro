# Dolt Schema Design for Cross-Organization Shared Tables

This document outlines a Dolt schema design to support shared tables across multiple organizations, enabling features like a shared cost ledger and cross-organization dependency tracking. The design emphasizes multi-tenancy through the consistent use of `org_id` where applicable.

## Table Definitions

### `organizations`

This table stores information about each organization within the system.

-   **Purpose:** To uniquely identify and manage organizations.
-   **Columns:**
    -   `org_id` (VARCHAR(36), PRIMARY KEY): Unique identifier for the organization (e.g., UUID).
    -   `name` (VARCHAR(255), NOT NULL): Name of the organization.
    -   `created_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP): Timestamp when the organization was created.
    -   `updated_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP): Timestamp of the last update.

### `users`

This table stores information about users, who can belong to one or more organizations.

-   **Purpose:** To manage user accounts and their association with organizations.
-   **Columns:**
    -   `user_id` (VARCHAR(36), PRIMARY KEY): Unique identifier for the user (e.g., UUID).
    -   `username` (VARCHAR(255), NOT NULL, UNIQUE): User's chosen username.
    -   `email` (VARCHAR(255), NOT NULL, UNIQUE): User's email address.
    -   `org_id` (VARCHAR(36), NOT NULL, FOREIGN KEY REFERENCES `organizations`(org_id)): The primary organization the user belongs to. This simplifies initial user creation but users can be associated with multiple orgs via a separate linking table if needed for more complex permissions.
    -   `created_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP): Timestamp when the user was created.
    -   `updated_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP): Timestamp of the last update.

### `projects`

This table stores information about projects, which are always associated with a specific organization.

-   **Purpose:** To organize work within an organization.
-   **Columns:**
    -   `project_id` (VARCHAR(36), PRIMARY KEY): Unique identifier for the project (e.g., UUID).
    -   `org_id` (VARCHAR(36), NOT NULL, FOREIGN KEY REFERENCES `organizations`(org_id)): The organization that owns this project.
    -   `name` (VARCHAR(255), NOT NULL): Name of the project.
    -   `description` (TEXT): Optional description of the project.
    -   `created_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP): Timestamp when the project was created.
    -   `updated_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP): Timestamp of the last update.
    -   **Unique Constraint:** `(org_id, name)` to ensure project names are unique within an organization.

### `cost_ledger`

This table tracks cost entries, which can be associated with an organization, a project, or even be cross-organizational if `org_id` is null or points to a "shared" org. For simplicity, we'll assume each cost entry belongs to a specific `org_id` and optionally a `project_id`.

-   **Purpose:** To record and track financial costs, enabling a shared cost ledger view across organizations.
-   **Columns:**
    -   `entry_id` (VARCHAR(36), PRIMARY KEY): Unique identifier for the cost entry (e.g., UUID).
    -   `org_id` (VARCHAR(36), NOT NULL, FOREIGN KEY REFERENCES `organizations`(org_id)): The organization incurring the cost. This is crucial for multi-tenancy.
    -   `project_id` (VARCHAR(36), FOREIGN KEY REFERENCES `projects`(project_id)): Optional project associated with the cost. Can be NULL for organization-level costs.
    -   `description` (TEXT): Description of the cost.
    -   `amount` (DECIMAL(10, 2), NOT NULL): The cost amount.
    -   `currency` (VARCHAR(3), NOT NULL): Currency code (e.g., USD, EUR).
    -   `entry_date` (DATE, NOT NULL): Date when the cost was incurred.
    -   `created_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP): Timestamp when the entry was created.
    -   `updated_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP): Timestamp of the last update.

### `dependencies`

This table tracks dependencies between entities, which could be projects, services, or other components. The `org_id` on both `source_entity_id` and `target_entity_id` allows for cross-organization dependency tracking.

-   **Purpose:** To track dependencies between various entities, potentially across organizations.
-   **Columns:**
    -   `dependency_id` (VARCHAR(36), PRIMARY KEY): Unique identifier for the dependency (e.g., UUID).
    -   `source_org_id` (VARCHAR(36), NOT NULL, FOREIGN KEY REFERENCES `organizations`(org_id)): The organization of the entity that has the dependency.
    -   `source_entity_id` (VARCHAR(36), NOT NULL): The ID of the entity that depends on another (e.g., `project_id`, `service_id`).
    -   `target_org_id` (VARCHAR(36), NOT NULL, FOREIGN KEY REFERENCES `organizations`(org_id)): The organization of the entity being depended upon.
    -   `target_entity_id` (VARCHAR(36), NOT NULL): The ID of the entity being depended upon.
    -   `dependency_type` (VARCHAR(50)): Type of dependency (e.g., "build", "runtime", "data").
    -   `description` (TEXT): Optional description of the dependency.
    -   `created_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP): Timestamp when the dependency was recorded.
    -   `updated_at` (TIMESTAMP, DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP): Timestamp of the last update.
    -   **Unique Constraint:** `(source_org_id, source_entity_id, target_org_id, target_entity_id, dependency_type)` to prevent duplicate dependency entries.

## Multi-Tenancy and Cross-Organization Sharing

The `org_id` column is central to enabling multi-tenancy and cross-organization sharing.

-   **`organizations`**: Serves as the root for all organizational data.
-   **`users`**: Users are primarily associated with an `org_id`. For scenarios where a user needs access to multiple organizations, a separate `user_organization_roles` table could be introduced.
-   **`projects`**: Each project is strictly owned by one `org_id`.
-   **`cost_ledger`**: Each cost entry is tied to an `org_id`. To view a "shared" cost ledger, queries would aggregate data across multiple `org_id`s, potentially with appropriate access controls.
-   **`dependencies`**: This table explicitly supports cross-organization dependencies by having separate `source_org_id` and `target_org_id` columns. This allows an entity in one organization to declare a dependency on an entity in another organization.

This schema provides a robust foundation for managing shared data across organizations within a Dolt database, leveraging its versioning capabilities for auditing and collaboration.