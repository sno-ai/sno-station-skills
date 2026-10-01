# Case Table — context anchor rows

This table holds the reference rows with numeric features that Step 5 uses as anchors.
`train-set.tsv` (51 cases, no numeric features) feeds only the class-level reality band.
Row ids use the `ctx-` prefix so they cannot be
confused with `train-set.tsv` ids.

**Anchor eligibility**: a row is usable as a Step-5 anchor only if every feature
and `actual_h` is a plain number — any `?`, `~`, `+`, or censored marker makes the
row INELIGIBLE (context only). Feature vector for distance (workload_class must
match exactly; others normalized 0–1 over table range, mean absolute difference;
eligible: distance ≤ 0.5 AND inside the magnitude window): `slices` ·
`runs`(= suite+smoke+e2e combined) · `deploy_cycles` ·
`novelty(mech=0/familiar=1/exploratory=2)`.

| case_id | class | novelty | slices | runs | deploy | actual_h | Evidence |
|---|---|---|---|---|---|---|---|
| ctx-01 | infra-agent-config | familiar | 1 | 1 | 0 | 0.2 | exact anchor |
| ctx-02 | source-code | mechanical | 2 | 4 | 0 | 3.6 | exact anchor |
| ctx-03 | source-code | familiar | 9 | 12 | 1 | 3.0+ | incomplete; censored for completion |
| ctx-04 | source-code | familiar | 11 | 10 | 0 | ~12 | approximate duration |
| ctx-05 | source-code | exploratory | 8 | 12 | 0 | ~9 | approximate duration |
| ctx-06 | source-code | familiar | 11 | 14 | 0 | ~9 | approximate duration |
| ctx-07 | infra-agent-config | exploratory | 5 | 0 | 0 | ~2.5 | approximate duration |
| ctx-08 | ui-web | exploratory | ? | ? | 1 | 4.0 | feature counts unknown |
| ctx-09 | ui-web | familiar | 3 | ? | 1 | ~0.3? | feature count and duration uncertain |
| ctx-10 | ui-web | familiar | 1 | 1 | 0 | 0.7 | exact anchor |

Notes:
- `ctx-03` is CENSORED for completion-time purposes (stopped before its
  goal); usable only for rate derivation, never as a completion anchor.
- `ui-web` rows are thin → any ui-web estimate is confidence `low` until the pool
  grows; every future UI journey is prioritized into this table.
- Reviewer sessions are NOT cases — they feed the reviewer-round rates in
  unit-rates.md.
