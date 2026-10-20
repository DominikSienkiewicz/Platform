# Build a feature test-first

**Preconditions:** the behaviour is small enough for one commit (one rule, one use case, one endpoint response),
the working tree is clean and the branch is green. A larger feature is a sequence of such behaviours: split it
first and run this runbook once per behaviour.

1. Write the acceptance criterion as Given/When/Then in the words of the domain, for example
   "Given an order with two lines, when one line is removed, then the total is the price of the other line".
   Keep it in the test name or the test itself, not only in the chat.
2. Write one test for that criterion in the module that owns the behaviour. Name it after the behaviour, not after
   the method it calls. Write the API the test needs as it should read; create only the empty production types and
   signatures that let the test compile.
3. Run only that test, never the module suite:
   `AI_AGENT=1 bash scripts/agent-gradle.sh test --tests <Class>`, narrowed to `--tests '<Class>.<method>'` when the
   class already holds other tests. For a test outside `test` (for example `integrationTest`), name that task
   instead. In a frontend, run `npx vitest run <file>`.
4. Read the failure. Red counts only when the test fails in its assertion, for the reason the criterion states.
   A compile error, a missing bean, a container that does not start or a test that is not found is not red: fix the
   test or the setup and run step 3 again.
5. Write the smallest production code that satisfies the criterion. Add no behaviour that no test asks for.
6. Run the same command as in step 3 until it is green.
7. Refactor production code and test with the test green, running step 3 after each change. Then run the default
   gate: `./gradlew lint`, with `./gradlew format` first when it reports formatting.
8. Commit the test and the code together, one commit per behaviour, so the branch is green in every commit. The
   type is `feat:`, or `refactor:` for a refactor that changes no behaviour. The body names the test that was red
   and why, for example:

   ```text
   feat(orders): recompute the total when a line is removed

   Red: OrderTest."removing a line recomputes the total" failed with
   expected 20.00 but was 35.00, because the total was cached at creation.
   ```

9. Run whole suites, integration tests and coverage only when the user asks for them.

**Done when:** the commit holds the new test and the code that makes it pass, its body names the red test and the
reason it failed, and the targeted run of step 3 and `./gradlew lint` are green.
