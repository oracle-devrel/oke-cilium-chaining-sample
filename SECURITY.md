<!-- Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved. -->
<!-- Author: Ulaganathan N -->

# Reporting security vulnerabilities

Oracle values the independent security research community and believes that
responsible disclosure of security vulnerabilities helps ensure the security
and privacy of all users.

Do not open a GitHub issue to report a security vulnerability. If you believe
you have found a security vulnerability, submit a report to
[secalert_us@oracle.com][1], preferably with a proof of concept. Review the
additional information about [reporting security vulnerabilities to Oracle][2].
Oracle encourages reporters to use email encryption with the published
[Oracle Security encryption key][3].

Do not use other channels or contact the project maintainers directly about a
suspected vulnerability.

Non-vulnerability security topics, including suggestions for safer defaults or
improved security features, may be discussed through normal repository issues.

## Security-related information

This repository contains sample infrastructure code. It is intended to
demonstrate OKE VCN-native pod networking with Cilium chaining and is not a
production landing-zone implementation. Review all network ranges, IAM
policies, Kubernetes versions, images, Terraform plans, and security rules for
the target environment before deployment.

[1]: mailto:secalert_us@oracle.com
[2]: https://www.oracle.com/corporate/security-practices/assurance/vulnerability/reporting.html
[3]: https://www.oracle.com/security-alerts/encryptionkey.html
