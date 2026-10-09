# Quarantined v0.9 implementation

These files are preserved only for audit and diff review. They are renamed
with `.disabled`, live outside the module root hooks, and are not included by
`tools/package_stage_b.py`.

They must not be restored to active paths without separate validation:

- `patch.sh` copied and patched `libaudiohal@aidl.so` during installation and
  every standard post-fs-data boot;
- it chose AIDL libraries by lexicographic filename order, rewrote DT_NEEDED,
  and copied newer libraries under older V2/V3 filenames;
- `aml.sh` sourced scripts from unrelated modules during installation;
- `service.sh` previously had a restart loop, direct bind mount, and
  audioserver restart;
- `sepolicy.rule` granted broad execute/map access unrelated to the minimum
  AML service policy.

Stage B intentionally replaces none of those behaviors. The prebuilt ELF
payloads are byte-identical and all compatibility decisions remain pending.
