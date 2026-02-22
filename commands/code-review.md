---
description: Asks the AI Agent to report it's findings on the previous use case implementation coding session
---

# Post-Implementation Review Instructions

You have now completed the implementation of this use case. Before we move on to the next task, conduct a thorough, honest, and critical self-review of the entire coding session.

## Step 1: Session Reflection

Review everything that happened from the moment you read $1 and $2 through to final verification. Identify:

- Any ambiguities, incomplete information, conflicting details, or assumptions that surfaced (even if resolved)
- Challenges encountered during codebase exploration, implementation, testing, or verification
- Instances where existing patterns, components, or guidelines helped or hindered progress
- Edge cases, error paths, performance/security/observability considerations that required extra effort
- Any gaps in the use case document, implementation plan, or `/docs/technical/use-case-implementation-guidelines.md` that became apparent
- Opportunities for reuse, simplification, or risk reduction that were not immediately obvious

## Step 2: Lessons Learned

Summarize the **key lessons learned** from this session. For each lesson:

- State it clearly and concisely
- Explain why it matters for production-grade software (maintainability, reliability, velocity, risk, etc.)
- Provide a concrete example from this use case (without repeating full code)

## Step 3: Process & Documentation Improvements

For every finding or lesson:

- Recommend **exactly where** in the document structure it should be captured so future use-case implementations automatically benefit.
- Prioritize these locations (in order of impact):
  1. `/docs/technical/use-case-implementation-guidelines.md` (specific section or new subsection)
  2. Relevant use-case template or checklist
  3. Architecture decision records or pattern library
  4. Any other project-standard location
- If a guideline update is warranted, provide the exact wording you would add or change (ready to copy-paste).

## Step 4: Overall Recommendations

- Rate the smoothness of this implementation (1–10) and explain the score.
- List 1–3 concrete actions we should take before the next use case to raise quality or velocity.
- Flag anything that should be added to the “common pitfalls” or “pre-implementation checklist” sections in the guidelines.

Be candid, precise, and forward-looking. The goal is continuous improvement of our delivery process, documentation, and engineering standards — not just completing this one use case.

Respond in the structured format above (use clear headings and bullet points). Do not proceed to any new work until this review is complete and I have acknowledged it.
