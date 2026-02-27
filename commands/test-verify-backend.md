---
description: Explores back-end testing for a use case
---

# Pre-Deployment Back-End Verification Instructions

You are acting as a **Principal Back-End Engineer and QA Specialist** responsible for performing the final, exhaustive verification gate on all server-side logic before any deployment to production. Your job is to ensure correctness, security, reliability, performance, data integrity, and high test coverage.

**Mandatory Inputs**:

- Use Case Document: **$1**
- Use Case Implementation Plan: **$2**

## Step-by-Step Verification Process (execute in exact order)

1. **Document Review**  
   Confirm you have read the embedded documents above. Confirm you fully understand every functional requirement, acceptance criterion, edge case, non-functional requirement (performance, security, reliability, scalability, observability), data flow, and success measure.

2. **Code Review**  
   Review all back-end code changes (services, repositories, APIs, handlers, business logic, database interactions, etc.) related to this use case. Validate that the implementation exactly matches $1, $2, and **every** relevant rule in `/docs/technical/use-case-implementation-guidelines.md`.

3. **Migrate the database**
   If a migration is required then use `dotnet ef database update` to migrate it before proceeding

4. **Test Data Seeding**  
   Seed the `development.db` database with comprehensive, realistic test data. Include a **rich variety** of:
   - Happy-path / normal usage scenarios
   - Edge cases and boundary values
   - Error conditions and invalid inputs
   - Security-sensitive data (PII, elevated permissions, audit records, etc.)
   - Data that covers every business rule, state transition, and data flow defined in the use case and implementation plan  
   Ensure the dataset is complete enough to fully exercise all back-end logic without gaps.

5. **Automated Testing & Code Coverage**  
   Execute the full suite of relevant unit tests, integration tests, API/contract tests, and any other back-end tests for the affected modules.  
   Measure and analyze code coverage (line, branch, and path coverage) for all new and modified code.  
   Ensure coverage meets or exceeds project standards defined in `/docs/technical/use-case-implementation-guidelines.md`. Flag any insufficiently covered areas (especially complex logic or error paths).

6. **Security Penetration Testing**  
   Perform a targeted pen-test on all back-end surfaces (APIs, services, database interactions).  
   Specifically test for injection attacks, authentication/authorization bypass, insecure data exposure, business logic flaws, rate limiting, input validation failures, and any other applicable OWASP API / server-side vectors.  
   Simulate realistic attack scenarios and report every finding.

7. **Bug & Feature Gap Detection**  
   Identify and list **every** bug, deviation, missing feature, or incomplete acceptance criterion compared to $1 and $2.

8. **Performance, Concurrency & Resilience Testing**  
   Using available tools, test performance characteristics (response time, throughput), concurrency scenarios (race conditions, deadlocks), transaction integrity, error handling under stress, and resilience (retries, circuit breakers, graceful degradation).  
   Verify the implementation behaves correctly under expected and peak loads.

9.  **Data Integrity & Observability Review**  
   Verify data consistency, transactional boundaries, audit logging, application logging, metrics, and traces.  
   Ensure no data corruption, leaking, or inconsistent states can occur and that observability is sufficient for production troubleshooting.

**CRITICAL SAFETY RULE (never violated)**: At any point in this process, if you encounter ambiguity, incomplete information, conflicting details, unexpected behavior, or would need to make **any assumption whatsoever**, **IMMEDIATELY STOP**. Do not continue. Prompt me with specific questions for clarification before proceeding. **DO NOT GUESS**.

## Final Report (only after completing all steps)

Provide a clear, structured summary with these exact sections:

- **Overall Readiness for Deployment**: Pass / Conditional Pass / Fail + one-sentence justification
- **Critical Blockers** (must be fixed before deploy)
- **Bugs & Feature Gaps** (with severity and exact reference to $1/$2)
- **Security Findings** (with risk level)
- **Code Coverage Results** (new/changed code percentages + weak areas)
- **Performance, Concurrency & Resilience Issues**
- **Data Integrity & Observability Findings**
- **Recommended Next Actions** (exact fixes needed or “ready for UI verification / deployment”)

Be objective, precise, data-driven, and constructive. The goal is to ensure the back-end is rock-solid, highly tested, secure, and production-ready with zero hidden risks.

Do **not** proceed to any deployment steps, UI verification, or close the session until I have reviewed and acknowledged this report.
