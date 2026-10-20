# Fix a bug test-first

**Preconditions:** the bug is reported with an input and the result that is wrong, the working tree is clean and
the branch is green. The fix lands as one `fix:` commit that holds the regression test and the production change.

1. Write the report as Given/When/Then: the state, the action, and the result the user expected instead of the one
   they got.
2. Write a regression test that reproduces it, in the module that owns the wrong behaviour and through the API the
   bug was reported against. It stays in the suite for good: name it after the behaviour, not after the ticket.
   End the class name in `Test`, `Tests`, `IT`, `ITCase` or `Spec`, so the red-proof job finds it.
3. Run only that test, never the module suite:
   `AI_AGENT=1 bash scripts/agent-gradle.sh test --tests <Class>`, narrowed to `--tests '<Class>.<method>'` when the
   class already holds other tests. In a frontend, run `npx vitest run <file>`.
4. Read the failure. The bug is reproduced only when the test fails in its assertion with the wrong result of the
   report, or with the exception the user saw. A compile error or a setup failure reproduces nothing: the test must
   compile against the code as it is, so change the test, not the production code, until it fails for the reason
   of the report.
5. Make the smallest production change that fixes it, then run the command of step 3 until it is green.
6. Run the default gate: `./gradlew lint`, with `./gradlew format` first when it reports formatting.
7. Commit the test and the fix together as `fix:`, one commit per bug. The body names the test that was red and
   why, for example:

   ```text
   fix(billing): round the VAT of each line before summing

   Red: InvoiceTest."VAT is rounded per line" failed with expected 2.46
   but was 2.47, because the VAT was rounded once on the sum.
   ```

8. When the repository calls backend-ci with `red-proof: true`, the `red-proof` job of its pull request runs the
   test classes this commit added or changed against the production code of the parent commit (the tests of the
   commit, `src/main` of its parent) and requires them to fail
   ([reusable workflows](../reusable-workflows.md#red-proof)). A `fix:` commit without a test class fails
   it with [PLAT-RED-001](../gates.md#plat-red-001), a test that passes on the parent with
   [PLAT-RED-002](../gates.md#plat-red-002), and a test that does not compile or run there with
   [PLAT-RED-003](../gates.md#plat-red-003).
9. Run whole suites, integration tests and coverage only when the user asks for them.

**Done when:** the `fix:` commit holds the regression test and the fix, its body names the red test and the reason
it failed, the targeted run of step 3 and `./gradlew lint` are green, and the `red-proof` job is green where the
repository enables it.
