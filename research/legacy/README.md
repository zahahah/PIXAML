# Quarantined v0.9 implementation

These files stay here for audit and diff review. They are renamed with
`.disabled`, live outside active module hooks, and are not packaged by
`tools/package_stage_c.py`.

Do not restore them to active paths without a separate validation plan:

- `patch.sh` copied and patched `libaudiohal@aidl.so` during installation and
  every standard post-fs-data boot;
- it chose AIDL libraries by lexicographic filename order, rewrote DT_NEEDED,
  and copied newer libraries under older V2/V3 filenames;
- `aml.sh` sourced scripts from unrelated modules during installation;
- `service.sh` previously had a restart loop, direct bind mount, and
  audioserver restart;
- `sepolicy.rule` granted broad execute/map access unrelated to the minimum
  AML service policy.

The current PIXAML path keeps those behaviors out of release builds. The
prebuilt ELF payloads remain byte-identical; every compatibility decision is
kept explicit so the module stays understandable and reversible.
