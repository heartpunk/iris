# Idris 2 Quality Gate Overrides

## Skip Mutation Testing

Mutation testing is not possible in Idris 2 (no mutmut/pitest/Stryker equivalent exists). Skip the mutation testing subagent during commit review. Run only 3 background review subagents: coverage, verification, and property tests.
