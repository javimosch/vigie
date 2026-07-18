# Functional tests

`./tests/functional.sh [./vigie]` — boots the real binary, exercises the real HTTP
endpoints and CLI verbs (no mocks, no unit-test framework; MFL has no line-coverage
tool, so **surface coverage** — routes × verbs × dims actually hit — is the metric).

Coverage: all 12 HTTP route-prefixes, all 18 CLI verbs, all 28 `stats` dimensions,
plus auth gating, semantic exit codes, filters, and the `/report` + `/globe` key flow.
89 assertions; exit 0 = all pass. Run after `./build.sh`.
