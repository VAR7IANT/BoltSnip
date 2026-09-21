# Release identity

`release.json` is the only editable source for the product name, release version,
and minimum supported version. Do not add version literals to source files,
installer scripts, or tests.

`build.ps1` generates the assembly attributes and application manifest under
`obj`, adds the UTC build time and Git commit as the build ID when available,
and validates the resulting `bin\BoltSnip.exe`. A repository without a commit
uses a `local-<UTC timestamp>` build ID.

`build-installer.ps1` reads the same identity before compiling the installer.
For a release, update `release.json`, build the executable, run all tests, then
build the installer. The build must fail if the assembly, file, product, or
installer identity diverges.
