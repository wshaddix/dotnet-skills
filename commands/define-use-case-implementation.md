---
description: Create a new use case implementation plan
---

# Instructions

Now let's design the technical architecture. Based on the use case document $1, help me decide:

1. How should the system be structured?
2. What are the key components and how do they interact?
3. What database schema do we need?
4. What APIs/endpoints are required?
5. Are there any third-party integrations?

Document key decisions and trade-offs. Reference the /docs/technical/technical-summary.md doc for learnings and guidance. Use any available skills that you think will be helpful. Also, always use Context7 MCP when you need library/API documentation, code generation, setup or configuration steps without me having to explicitly ask. Show me any updates that you want to make to the technical-summary.md document BEFORE you make them. You MUST get approval before updating it.

Once complete, update the /docs/domain-model.md with our findings and review it for accuracy. If you find anything in the code base that is in conflict with what is in the domain-model.md STOP and prompt me for clarification on how to proceed.

You MUST adhere to everything from the /docs/technical/use-case-implementation-guidelines.md file. If you find anything missing or incorrect, STOP and prompt me for clarification and decision on how to proceed.

BEFORE you proceed with the actual technical architecture implementation, I want you to create a new file alongside of $1 that describes every detail of the implementation plan that you would need to create and verify the code. Imagine that you are starting with no context at all .... nothing that we have discussed and/or decided is available to you. The only thing that you will have access to is this document that you are about to create. Ensure that you detail any and everything you would need to complete this task using only this new document. Name it the same as $1 except add a "-PLAN.md" suffix to the file name and wait for me to review that file before proceeding. I'm going to test you by starting a new session and asking you to read this new file that you create, so make sure you put your best effort into it.
