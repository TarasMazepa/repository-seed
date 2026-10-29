# Release Naming Standards

To maintain a cohesive and professional ecosystem across all our repositories, we use the **Formal Suite** naming convention for all GitHub Releases. This ensures that as our projects grow to include multiple artifacts (e.g., CLIs, Desktop Apps, Web UIs), our changelogs remain clear, unambiguous, and highly scannable.

## 1. The Standard Format

All release titles must strictly follow this format:

> **`[Project Name] [Subsystem] v$VERSION`**

### Component Definitions
* **`[Project Name]`**: The capitalized, formal name of the overarching product (e.g., Monoapp, Stax).
* **`[Subsystem]`**: The capitalized name of the specific artifact or interface being released (e.g., CLI, App, UI, Server).
* **`v$VERSION`**: The literal semantic version number prefixed by a lowercase `v` (e.g., v1.0.0, v0.11.8).

## 2. Authorized Examples

Here is how this standard applies across our current and future project topography:

### The Monoapp Ecosystem
* **Terminal Binary (`mna`):** `Monoapp CLI v1.0.0`
* **Graphical Interface:** `Monoapp App v1.0.0`
* **Backend Services:** `Monoapp Server v1.0.0`

### The Stax Ecosystem
* **Terminal Binary:** `Stax CLI v0.11.8`
* **Graphical Interface:** `Stax UI v1.0.0`

## 3. Automation and CI/CD Rules

When automating releases via GitHub Actions or the `gh` CLI, this formal title must be explicitly constructed in the pipeline. It must be decoupled from the raw Git tag format.

* **Git Tags:** Monorepo git tags should continue using a routing prefix to trigger specific workflows (e.g., `cli-v1.0.0` or `app-v1.0.0`).
* **Release Titles:** Do **not** use the raw Git tag as the release title. Extract the raw semantic version and construct the formal title as defined above.
* **Changelogs:** Always use the `--generate-notes` flag in CI to map commit history to the release, ensuring a clean, automated changelog.

**Example CI Implementation (`gh` CLI):**
```bash
# Extract the raw version (e.g., 1.0.0)
VERSION=$(cat cli/VERSION)

# Define the Git tag for the monorepo trigger
TAG="cli-v$VERSION"

# Construct the formal release title
RELEASE_TITLE="Monoapp CLI v$VERSION"

# Create the release
gh release create "$TAG" --title "$RELEASE_TITLE" --generate-notes

```

## 4. Adding New Subsystems

If a new artifact is introduced to the repository (e.g., an API gateway, browser extension, or mobile client), follow the established pattern by defining a clear, single-word or short-phrase `[Subsystem]` identifier. Update this document with the new authorized example before publishing the first release.
