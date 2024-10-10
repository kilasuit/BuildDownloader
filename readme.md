## The Why behind this repo

Output from this issue <https://github.com/PowerShell/PowerShell/issues/24081> - Add mechanism to more easily download a build artifact  

Designed for how the PowerShell Repo currently builds PR's but is very easily able to be adapted for any PR across GitHub repos (GitHub.com) that uses a public Azure Pipeline as part of build/test.

#### Some points

- gh cli just makes it simpler for the GH api calls
- Naming choices is interesting & *maybe* confusing between
- Goal to run from about anywhere and not need a clone of repo to do any manual testing of a build, like User Experience tests
- Useful for community members that may want latest bits of a specific PR during it's development and merge cycle
- Useful for injection and testing in areas like
  - Sandbox
  - Virtual Machines
  - Containers
  - or other places PS runs
- Useful for keeping dev/admin machines tidy(ish)
  - especially lower spec'd machines
- Build artifacts are **NOT** a replacement for an official release

#### Future Efforts

-
