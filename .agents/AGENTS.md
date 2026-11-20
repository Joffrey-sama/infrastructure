# Agent Rules — `infrastructure` (Public Context-Agnostic Repo)

## Communication & Language
- **User chat**: Natural, concise French.
- **Technical artifacts**: English ONLY (code, YAML keys/comments, docs, branches, commits, PRs).

## Repo Scope & Agnostic Design
- Contains strictly **public, generic, reusable** components:
  - Helm charts (`kubernetes/charts/*`)
  - Ansible collection `joffrey_sama.infrastructure` (`ansible/roles/*`, `ansible/playbooks/*`)
  - Terraform modules (`terraform/modules/*`)
  - Reusable GitHub Actions workflows (`.github/workflows/*`)
- **Zero environment specifics**: NEVER hardcode private IPs (`192.168.1.x`), private domains (`*.delva-home.fr`), cluster-specific annotations (e.g., `sidecar.istio.io/inject`), or secrets. Expose configurable variables with empty/neutral defaults (`podAnnotations: {}`, `subnets: []`).
- **Strict SemVer & Zero Floating Tags**: NEVER use `@main`, `@master`, `:latest`, or major-only `@vX` when exact SemVer tags exist. Pin all GitHub Actions, container images, Terraform modules, and Helm dependencies to exact versions (`vX.Y.Z`) for Renovate tracking.

## Project Management (GitHub Projects & Issues)
- The GitHub Projects Kanban board on `Joffrey-sama/delva-home-ops` and its Issues are the single source of truth for roadmap and tracking.
- When starting a task, move its card to `In progress`.
- Reference cross-repo issues in PR descriptions:
  - `Part of Joffrey-sama/delva-home-ops#<id>` for intermediate/reusable steps.
  - `Closes Joffrey-sama/delva-home-ops#<id>` only when the issue requires no follow-up ops PR.

## GitOps & Execution Guardrails
- **Strict GitOps (Flux v2)**: Design all charts and manifests for declarative Flux v2 reconciliation. Imperative cluster changes (`helm install/upgrade`, `kubectl apply`) are forbidden.
- **Read-only autonomy**: Run inspection, diff, and dry-run commands (`kubectl get/describe/diff/logs`, `helm template/diff/lint`, `ansible-playbook --check --diff`, `terraform plan/validate`, `git status/log/diff`) without asking permission.
- **Antigravity CLI syntax**: Always place the subcommand immediately after the binary (e.g., `kubectl get pods -n <ns>`, NEVER `kubectl -n <ns> get pods` or `--context` before subcommand). Never use shell pipes (`|`), redirections (`>`), chaining (`&&`, `;`), or command substitution (`$(...)`).
- **Approval before mutations**: Always present a plan/diff and ask user confirmation before modifying files, deleting files/directories, or running mutating commands.
- **Stop on failure & cadence**: Stop immediately on any unexpected error (never auto-recover/retry blindly) and report clearly. Stop and summarize progress after at most **7 consecutive commands**.
- **Conceptual questions**: Answer architecture/explanation questions directly in prose without running terminal commands.