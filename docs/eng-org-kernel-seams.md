# Architectural Seams: `eng-org` and the Keiro Kernel

This document outlines the architectural boundary between the general-purpose Keiro kernel and the specific implementation for a software engineering organization, `eng-org`. Understanding this seam is crucial for extracting the kernel into a reusable SDK and for guiding future authors in creating new organizational structures on top of Keiro.

## 1. General Patterns (The Kernel)

The Keiro kernel is composed of three main crates: `kernel`, `router`, and `memory`. These crates provide the core abstractions and functionalities that are domain-agnostic.

### `kernel`
- **Core Traits:** Defines the fundamental contracts for the system:
    - `Org`: Represents an entire organizational structure.
    - `Pipeline`: Defines a sequence of stages to accomplish a task.
    - `Agent`: Represents an autonomous entity that performs work within a pipeline stage.
- **Data Structures:** Provides standardized types for communication and state management:
    - `Message`, `MessageRole`: For agent-LLM communication.
    - `ToolDefinition`, `ToolCall`, `ToolResult`: For defining and executing tools.
    - `PipelineStatus`, `ObstacleKind`: For detailed status reporting and structured error handling.
- **Core Services:**
    - `ContextAssembler`: A priority-based system for assembling context for agents.
    - `BudgetTracker`: Enforces token and cost limits on a per-task basis.
    - `ApprovedAction<T>`: A type-level governance mechanism to enforce constraints.

### `router`
- **Provider Abstraction:** Decouples the core logic from specific LLM providers.
    - `Router`: A central point for all LLM calls (`complete`, `complete_with_tools`).
    - `Provider` trait: A common interface for different LLM APIs (e.g., Anthropic, OpenAI, Gemini).
- **Intelligent Routing:**
    - `ModelChooser`: Selects the best model for a given task based on tiers, profiles, and preferences.
- **Diagnostics:** Provides tools for understanding and classifying provider-level errors.

### `memory`
- **Persistence Layer:** Abstracts away the details of data storage.
    - `HistoryBackend`: A trait for storing and retrieving conversation history.
    - Concrete implementations are provided (e.g., JSONL), but the interface allows for extension.

## 2. Engineering-Specific Patterns (`eng-org`)

The `eng-org` crate is a concrete, domain-specific implementation of a software engineering organization built on top of the kernel. It is complex and tailored to the nuances of code generation and repository management.

- **`EngineeringPipeline`:** A massive, multi-stage implementation of the `Pipeline` trait. Its stages (e.g., `index`, `plan`, `triage`, `implement`, `test`) represent a complete software development lifecycle.
- **Specialized Agents:** A suite of agents, each implementing the `Agent` trait, designed for specific software engineering tasks:
    - `PlannerAgent`: Decomposes tasks.
    - `ImplementerAgent`: Writes and modifies code using tools.
    - `DebuggerAgent`: Fixes failing tests.
    - `SecurityAgent`, `ArchitectReviewAgent`, etc.
- **`Orchestrator`:** A high-level process manager that runs tasks from a queue, manages Git worktrees for isolation, handles retries, and tracks cumulative budgets across multiple tasks.
- **Domain-Specific Tooling:** Concrete implementations of tools required for software development: `read_file`, `write_file`, `edit_file`, `run_command`.
- **Configuration & State:**
    - `EngConfig`: A rich, YAML-based configuration structure.
    - `TaskQueue`: Manages the queue of development tasks.
- **Code Understanding:**
    - `RepoIndex`: A system for indexing a codebase to provide relevant context to agents.
- **Quality & Analysis:**
    - `TQMAnalyzer`: A system for detecting failure patterns (`PatternKind`) to improve process reliability.

## 3. Interaction Points & Seams

`eng-org` is a consumer of the kernel's abstractions. The relationship is a clear example of "implementing an interface."

- **Trait Implementation:** The primary seam is the implementation of kernel traits. `EngineeringPipeline` implements `kernel::Pipeline`, and all agents in `eng-org/src/agents/` implement `kernel::Agent`. `eng-org` itself is a concrete `kernel::Org`.
- **Service Usage:** The `Orchestrator` and agents in `eng-org` use the `router::Router` for all LLM communication, benefiting from provider-agnosticism and centralized budget tracking.
- **Data Flow:** `eng-org` uses the kernel's data structures extensively. Agent communication is structured via `kernel::Message`, and all tool interactions use `kernel::ToolCall` and `kernel::ToolResult`.
- **Context Assembly:** The `build_user_message` function in `eng-org` is a domain-specific strategy that leverages the general `kernel::ContextAssembler` to prepare inputs for its agents at each pipeline stage.

## 4. Implications

### For Kernel Extraction

The current structure is well-suited for extracting a general-purpose kernel.
1.  The `kernel`, `router`, and `memory` crates can be bundled into a standalone SDK.
2.  `eng-org` serves as a perfect, albeit complex, example of how to use this SDK.
3.  The `Org` trait is the main entry point for a new implementation. The SDK would document that users must provide an `Org` implementation.

### For Future Org Authors

Authors creating new organizations (e.g., `legal-org`, `marketing-org`) can follow the pattern set by `eng-org`.
1.  **Start with the Traits:** Implement `Org`, `Pipeline`, and a set of `Agent`s for the target domain.
2.  **Define the Workflow:** Design the stages of your `Pipeline` to reflect the domain's process.
3.  **Implement Tools:** Create a set of tools that your agents will need to need to interact with their specific environment (e.g., document databases, APIs, etc.).
4.  **Configure, Don't Rebuild:** Reuse the `router` and `memory` crates by providing configuration. There is no need to rebuild LLM routing or history management.
5.  **Reference `eng-org`:** Use `eng-org` as a guide for structuring the orchestrator, configuration, and agent implementations. While the specific logic is different, the patterns for wiring components together are reusable.
