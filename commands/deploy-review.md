---
description: Reviews the deployment process for any issues and/or lessons learned
---

# Post-Deployment Review Instructions

You have now completed the deployment of this use case to production. Before we proceed to any new work, conduct a thorough, honest, and critical self-review of the entire deployment process.

## Step 1: Deployment Reflection

Review the full deployment lifecycle — from preparation and execution through post-deployment monitoring, verification, and initial stabilization. Identify:

- Any issues, errors, delays, rollbacks, or unexpected behaviors encountered
- Gaps or ambiguities in deployment instructions, checklists, or validation steps
- Differences between expected and actual production behavior (stability, performance, observability, user impact)
- Friction points, manual steps, coordination needs, or risk areas that surfaced
- Elements of the process that worked especially well and should be reinforced
- Any assumptions made or documentation shortfalls that became visible only in production

## Step 2: Lessons Learned

Summarize the **key lessons learned** from this deployment. For each lesson:

- State it clearly and concisely
- Explain why it matters for safe, repeatable, low-risk production deployments
- Provide a concrete example from this use case deployment

## Step 3: Process & Documentation Improvements

For every finding or lesson:

- Recommend **exactly where** in the document structure it should be captured so future deployments automatically benefit
- Prioritize these locations (in order of impact):
  1. `/docs/technical/deployment-guidelines.md` (specific section or new subsection)
  2. Relevant deployment checklist, template, or playbook
  3. Any shared operations or architecture standards
  4. `/docs/technical/use-case-implementation-guidelines.md` (if the lesson applies upstream to implementation)
- If a guideline update is warranted, provide the exact wording you would add or change (ready to copy-paste)

## Step 4: Overall Recommendations

- Rate the smoothness and safety of this deployment (1–10) and explain the score
- List 1–3 concrete actions we should take before the next deployment to raise quality, speed, or reliability
- Flag anything that should be added to “common deployment pitfalls” or “pre-deployment checklist” sections

Be candid, precise, and forward-looking. The goal is continuous maturation of our deployment practices, documentation, and production safety — not just marking this release complete.

Respond strictly in the structured format above (clear headings and bullet points). Do not proceed to any new tasks until this review is complete and I have acknowledged it.
