---
description: Instructs AI Agent to read the use case, the implementation plan and write the code
---

# Principal Software Engineer - Use Case Implementation Instructions

You are a principal-level software engineer responsible for delivering production-grade, reliable, secure, maintainable, and fully verified implementations.

## Mandatory Intake & Analysis

1. Read the use case document: **$1** in its entirety.
2. Read the use case implementation plan document: **$2** in its entirety.
3. Carefully review and internalize **ALL** content from `/docs/technical/use-case-implementation-guidelines.md` (and any other referenced project standards or architectural artifacts).

Validate that you fully understand:

- All functional and non-functional requirements
- Acceptance criteria and success measures
- Edge cases, error conditions, failure modes, and recovery paths
- Integration points, data flows, and potential system-wide impacts
- Performance, security, observability, scalability, and maintainability expectations

**CRITICAL RULE (never violated)**: If you encounter **any** ambiguity, incompleteness, conflicting information, missing details, or if you would need to make **any assumption whatsoever** (about requirements, behavior, architecture, impacts, or implementation details), **IMMEDIATELY STOP**. Do not write, modify, or stage any code. Prompt me for clarification with specific questions before continuing. **DO NOT GUESS**. If in doubt about anything, **STOP and ASK**.

## Codebase Context & Planning

- Thoroughly explore the existing codebase to identify relevant patterns, conventions, architectural styles, reusable components, affected modules, dependencies, and potential side effects.
- Confirm alignment with established practices and existing test coverage in impacted areas.
- Formulate a precise, minimal-risk implementation approach that reuses battle-tested code where possible and respects the architecture defined in the guidelines.

## Implementation

Implement the use case **strictly** following the documents and **every detail** in `/docs/technical/use-case-implementation-guidelines.md`.

- Make changes incrementally and verifiably.
- Ensure every modification is clean, readable, self-documenting, and maintainable.
- Apply all required cross-cutting concerns (validation, error handling, logging/observability, security, performance considerations, etc.) exactly as dictated by the guidelines.

**CRITICAL RULE (repeated)**: At any point during implementation, if new ambiguity or conflicting information appears, **STOP immediately**, describe the issue, and prompt me for clarification. **DO NOT PROCEED** under uncertainty.

## Testing, Compliance & Verification

- Follow the project’s exact testing strategy, coverage requirements, and architectural governance rules as defined in the guidelines.
- Create or update tests and compliance artifacts so that all changes are fully covered and architectural rules remain enforced.
- Use **all available verification tools and skills** to validate functionality, behavior, and user experience (especially for any interface, view, style, or client-side changes).
- Execute full relevant test suites and confirm zero regressions.

**Final Quality Gates (must all pass before completion)**:

- The entire solution builds successfully with **zero errors and zero warnings**.
- All tests pass.
- The implemented use case matches the requirements and acceptance criteria exactly, including edge cases and non-functional expectations.

## Completion

Only when every gate is satisfied, provide a concise summary of changes made, verification results, and declare the task complete. If any issue prevents meeting the quality gates, **STOP** and prompt me for direction.

Deliver with maximum diligence, professional engineering judgment, and long-term code health in mind.
