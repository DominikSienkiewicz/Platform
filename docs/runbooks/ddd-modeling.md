# Model a domain with DDD

**Preconditions:** a domain change is asked for (a new capability, a module split, a rule that does not fit the
current model), and the people who know the domain, or their written requirements, are at hand. The model comes
first; each behaviour of it is then built with [build a feature test-first](tdd-feature.md).

1. **Ubiquitous language.** Collect the terms of the domain in a glossary in the repository (for example
   `GLOSSARY.md` at its root): each term, its meaning in one sentence, and the bounded context it belongs to. Use these
   words in class, method, package and test names; a term that means two things is a sign of two contexts.
2. **Bounded contexts and their map.** Name each context, the language it owns and the team or module that owns
   it. Draw the context map: for each pair that talks, the relation (customer and supplier, conformist,
   anticorruption layer, shared kernel, published language) and the direction of the dependency. Keep the map
   beside the glossary; a Mermaid diagram is enough.
3. **One context, one module.** Map each context to one Spring Modulith application module (a top-level package)
   or one Gradle module. Other modules reach it only through its published API: the types of its root package and
   its events. Everything else stays package-private or in an `internal` package.
4. **Choose the building block for each concept**, the simplest that holds its rules:
   - a **value object** for a concept defined by its value and immutable (money, an e-mail address, a date
     range), validated in its constructor;
   - an **entity** for a concept with an identity that outlives a change of its attributes;
   - an **aggregate** only around a rule that must hold in one transaction (an invariant across several
     entities); the root is the only entry point, other aggregates are referenced by identity, and one
     transaction changes one aggregate;
   - a **domain service** for a rule that belongs to no single entity or value object;
   - a **domain event** when another module or context reacts to a change, published through Spring Modulith
     events instead of a direct call;
   - a **port with an adapter** only where the domain must not know the technology behind it (a database, a
     message broker, a third-party API) or where a second implementation exists or is planned with a date.
   Use no pattern in advance: no repository interface with one implementation and no reason to swap it, no
   factory for a plain constructor, no event that nobody consumes.
5. **Record each pattern in an ADR** in the repository's ADR directory (for example `docs/adr/`): the context,
   the decision, the alternatives that were rejected and why, and the consequences. A pattern without an ADR is
   not yet chosen; an ADR whose reason no longer holds is superseded by a new one, not edited.
6. **Verify the boundaries with a test.** With Spring Modulith, extend `AbstractModulithVerificationTest` of
   `pl.seniordeveloper:platform-test-fixtures`, which runs `ApplicationModules.of(<Application>.class).verify()`,
   and `AbstractModulithDocumentationTest` of the same artifact renders the module diagram. Without Spring Modulith,
   write ArchUnit rules; `PlatformArchRules` and `HexagonalRules` hold the shared ones. Write this test first and
   observe it red on a forbidden dependency, as in [build a feature test-first](tdd-feature.md).
7. Implement each behaviour of the model with [build a feature test-first](tdd-feature.md), one commit per
   behaviour, using the glossary's words in the Given/When/Then.

**Done when:** the glossary and the context map name every context the change touches, each new pattern has an ADR
with its rejected alternatives, and the boundary test of step 6 is in the suite and green.
