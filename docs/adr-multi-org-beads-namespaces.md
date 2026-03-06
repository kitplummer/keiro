# ADR 00XX: Multi-Organization Beads Namespaces

## Status
Proposed

## Context
Keiro is evolving to support multiple organizations sharing the same repository. This introduces challenges in managing "beads" – reusable components or configurations – to ensure isolation, prevent naming collisions, and enable controlled sharing across organizations. Specifically, we need a clear design for how beads namespaces will operate in a multi-organization environment, addressing unique identification, organization-specific configurations, and cross-organization references.

## Problem Statement
When multiple organizations share a single Keiro repository, the current bead management system may lead to:
1. **Naming Collisions:** Different organizations might inadvertently create beads with the same name, leading to conflicts.
2. **Lack of Isolation:** Configurations or components intended for one organization might inadvertently affect another.
3. **Complex Configuration:** Managing organization-specific settings for beads can become cumbersome without a clear strategy.
4. **Uncontrolled Sharing:** While some sharing might be desirable, uncontrolled or accidental sharing of beads could lead to security or operational issues.

## Decision
We will implement a multi-organization beads namespace design based on the following principles:

### 1. Prefix Partitioning for Unique Identification
Each organization will be assigned a unique, immutable prefix. All beads created by an organization MUST be prefixed with their assigned organizational prefix.

*   **Format:** `<org_prefix>::<bead_name>`
*   **Example:** `orgA::my-service-bead`, `orgB::data-pipeline-bead`
*   **Rationale:** This ensures global uniqueness for bead names within the shared repository, preventing naming collisions and clearly attributing ownership. It also simplifies access control and auditing.

### 2. Rig-per-Org Configuration Strategy
Each organization will have its own dedicated "rig" configuration. A rig defines the set of beads available to an organization, their versions, and any organization-specific parameters or overrides.

*   **Mechanism:** A dedicated configuration file or section (e.g., `rigs/<org_prefix>.yaml`) will define the beads and their configurations for that specific organization.
*   **Benefits:**
    *   **Isolation:** Changes to one organization's rig do not affect others.
    *   **Customization:** Allows organizations to use different versions of shared beads or override default parameters.
    *   **Clear Ownership:** Each rig is explicitly owned and managed by its respective organization.

### 3. Controlled Cross-Organization References
While isolation is key, there will be scenarios where organizations need to reference or utilize beads from another organization. This will be explicitly controlled and opt-in.

*   **Mechanism:** An organization's rig can explicitly declare a dependency on a bead from another organization. This declaration will include the full prefixed name of the bead and optionally a specific version.
*   **Example in `rigs/orgB.yaml`:**
    ```yaml
    beads:
      - name: orgB::my-app
        version: 1.0.0
      - name: orgA::shared-library-bead # Explicit reference
        version: 2.1.0
        parameters:
          api_key: "..." # Org-specific override
    ```
*   **Controls:**
    *   **Explicit Opt-in:** Beads are not shared by default. The owning organization must explicitly mark a bead as "shareable" or "public" within its own rig or bead definition.
    *   **Version Pinning:** Referenced beads must be version-pinned to ensure stability and prevent unexpected breaking changes.
    *   **Access Control:** Keiro's access control mechanisms will enforce that only authorized organizations can declare dependencies on shared beads.

## Rationale
This design provides a robust framework for multi-organization support by:
*   **Enforcing Uniqueness:** Prefixing eliminates naming conflicts.
*   **Ensuring Isolation:** Rig-per-org provides clear boundaries for configuration.
*   **Enabling Controlled Sharing:** Explicit references and opt-in mechanisms allow for collaboration without sacrificing security or stability.
*   **Scalability:** The system can scale to many organizations without significant architectural changes.

## Implications
*   **Tooling Updates:** Keiro tooling will need to be updated to enforce prefixing, manage rig configurations, and resolve cross-organization bead references.
*   **Migration Strategy:** Existing single-organization repositories will need a migration path to adopt the prefixing convention.
*   **Documentation:** Clear guidelines for organizations on how to name, configure, and share beads will be essential.
*   **Security:** Access control policies must be carefully designed and implemented to govern cross-organization bead access.

## Alternatives Considered
*   **Separate Repositories per Org:** While offering ultimate isolation, this approach introduces significant operational overhead for managing shared infrastructure and code, and goes against the premise of sharing a single repository.
*   **Global Namespace with Strict Naming Conventions:** Relying solely on naming conventions without enforced prefixing is prone to human error and difficult to scale.
*   **Implicit Sharing:** Allowing beads to be shared by default would lead to a lack of control and potential security vulnerabilities.

## Future Considerations
*   **Bead Discovery:** Mechanisms for organizations to discover shareable beads from other organizations.
*   **Dependency Graph Visualization:** Tools to visualize cross-organization bead dependencies.
*   **Automated Prefix Assignment:** A system for automatically assigning and managing organization prefixes.
