---
description: Instructs AI Agent to read the use case, the implementation plan and write the code
---

# Instructions

Read $1 and then $2 and verify that you understand what the use case is and how to implement it. IMPORTANT: YOU MUST FOLLOW ALL GUIDEANCE from /docs/technical/use-case-implementation-guidelines.md. If there is any ambiguity, STOP and prompt me for clarification. Use any and all skills available to you to implement the code and most importantly verify your work. If you ever come to incomplete, ambiguous, and/or conflicting information, STOP and prompt me for clarification and direction. DO NOT GUESS at what you need to do, if in doubt, STOP and ASK. When you write C# code, make sure you write corresponding unit tests in the Unit.Tests project. When you add, modify or remove C# code, make sure it's covered by an existing Architecture Test in the Architecture.Tests project. If it's not, create the necessary tests and make sure they pass. If you write or modify Razor page, CSS, Javascript, make sure you use the agent-browser skill to verify your work. The solution should build with no errors and no warnings before you are done.
