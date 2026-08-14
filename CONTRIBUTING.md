<!-- Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved. -->
<!-- Author: Ulaganathan N -->

# Contributing to this repository

We welcome contributions to improve this sample.

## Opening issues

For bugs or enhancement requests, open an issue and include the environment,
the command that was run, the expected result, and the observed result. Do not
open a public issue for a suspected security vulnerability. Follow the
instructions in [SECURITY.md](SECURITY.md) instead.

## Contributing code

Before submitting code through a pull request, you must sign the
[Oracle Contributor Agreement][OCA]. Commits must include a `Signed-off-by`
line containing the name and email address used to sign the OCA. Add the line
automatically from your configured Git identity by committing with `--signoff`
or `-s`:

```bash
git commit --signoff
```

Only contributions from committers who can be verified as having signed the
OCA can be accepted.

## Pull request process

1. Open an issue to describe and discuss the intended change.
2. Fork the repository and create a focused branch for the issue.
3. Keep the Terraform, shell scripts, documentation, and examples consistent.
4. Run `terraform fmt -check -recursive` and `bash -n scripts/*.sh`.
5. For behavioral changes, include validation evidence from the relevant
   deployment or smoke-test workflow without including credentials or secrets.
6. Submit a pull request that references the issue and explains how reviewers
   can reproduce the result.
7. Obtain the required OSSA Lite buddy review before merging.

## Code of conduct

Follow the [Golden Rule](https://en.wikipedia.org/wiki/Golden_Rule). For more
specific guidance, see the [Contributor Covenant Code of Conduct][COC].

[OCA]: https://oca.opensource.oracle.com
[COC]: https://www.contributor-covenant.org/version/1/4/code-of-conduct/
