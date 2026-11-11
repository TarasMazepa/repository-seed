# MORE AGENTS

Instructions and protocols for autonomous agents working in `repository-seed`.

---

## 1. Role & Architecture of `repository-seed`

- **Central Upstream Source of Truth**: This repository centrally defines and maintains shared configurations:
  - Root agent guidelines: [`AGENTS.md`](AGENTS.md)
  - Centrally synchronized documentation: [`docs/from-seed/`](docs/from-seed/)
- **Self-Contained Seed Documentation**: Seed files in `docs/from-seed/` must remain self-contained. Do not hardcode links or references to private downstream repositories or personal data unless referencing open source tools (like `stax` or `tbx-for-toolbox.dev`).
- **Automated Propagation Matrix**: Pushes to `main` touching `AGENTS.md` or `docs/from-seed/**` automatically trigger [`.github/workflows/on-seed-updated.yml`](.github/workflows/on-seed-updated.yml). This workflow creates branches (`update-from-seed-${GITHUB_RUN_ID}`), opens pull requests, and enables auto-merge across all participating repositories in the estate.

---

## 2. Seed Propagation & PR Monitoring Protocol

Whenever you land changes on `main` in `repository-seed`, merge a pull request, or are asked to audit seed propagation status, execute the following protocol:

### Step 1: Monitor the Upstream Workflow Run
Check that the central `on-seed-updated.yml` workflow was triggered and all matrix jobs succeed:
```bash
# View recent workflow runs
gh run list --workflow on-seed-updated.yml --limit 3

# Watch an in-progress workflow run until completion
gh run watch <run-id>
```
Or execute the local monitor script:
```bash
./scripts/monitor-seed-propagation.sh --watch
```

### Step 2: Audit Downstream Pull Requests
Verify that downstream seed update pull requests are created and successfully auto-merged:
```bash
# Run the seed monitor script to inspect open vs. merged PRs and CI checks
./scripts/monitor-seed-propagation.sh

# Or search open seed pull requests across the ecosystem directly
gh search prs --owner TarasMazepa --state open "Changes from repository seed"
```
Under normal conditions, all downstream PRs merge automatically within 1–2 minutes, leaving **0 open seed PRs**.

### Step 3: Triage Blocked or Failing Seed PRs
If any downstream seed PR remains open, auto-merge is blocked. The primary cause is failing CI checks in that downstream repository:
1. **Inspect failing checks**:
   ```bash
   gh pr checks <pr-url>
   ```
2. **View failed workflow logs**:
   ```bash
   gh run view <run-id> --repo <owner/repo> --log-failed
   ```
3. **Classify the failure**:
   - **Seed-Introduced Regression**: e.g., Markdown link validation failure due to broken relative links or invalid syntax in new seed files. *Fix the issue immediately in `repository-seed` and land on `main`.*
   - **Pre-Existing Downstream Failure**: e.g., strict linting failures on unrelated application code (such as SDK deprecation warnings or unrelated test failures). *Document and report the affected repository, run ID, and exact failure reason to the user.*

---

## 3. Integration with `tbx-for-toolbox.dev` Tools

Use the ecosystem health auditing tools in `~/tbx-for-toolbox.dev` to monitor open PRs and CI status across all repositories:

- **Audit Open PRs across all repositories**:
  ```bash
  ~/tbx-for-toolbox.dev/tbx-gh-prs.sh
  ```
  *(Pass `-r` or `--ready` for non-draft PRs, or `--repo <name>` for a single repository).*

- **Audit Failing GitHub Actions CI and Crons**:
  ```bash
  ~/tbx-for-toolbox.dev/tbx-gh-actions.sh
  ```
  *(Pass `--days 7` or `--repo <name>` to scope inspections).*

- **Unified Global GitHub Health Dashboard**:
  ```bash
  ~/tbx-for-toolbox.dev/tbx-gh-status.sh
  ```
  *(Runs a comprehensive health check covering all open PRs and broken workflows across the estate).*
