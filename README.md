<p align="center">
  <a href="https://hotcfg.run">
    <img src=".github/hotcfg-logo-card.svg" alt="hotcfg.run" width="300">
  </a>
</p>

<h1 align="center">hotcfg GitHub Action</h1>

<p align="center">
  Schema-checked remote JSON config, shipped from your CI.<br>
  Check config files on every pull request, push them to <a href="https://hotcfg.run">hotcfg.run</a> on merge, and promote them to production.
</p>

<p align="center">
  <a href="https://github.com/marketplace/actions/hotcfg"><img alt="GitHub Marketplace" src="https://img.shields.io/badge/marketplace-hotcfg-FF4F12?logo=github"></a>
  <a href="https://github.com/hotcfg/action/actions/workflows/test.yml"><img alt="Test" src="https://github.com/hotcfg/action/actions/workflows/test.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue"></a>
  <a href="https://hotcfg.run/docs/guides/ci"><img alt="Docs" src="https://img.shields.io/badge/docs-hotcfg.run-18181B"></a>
</p>

---

The action installs the [hotcfg CLI](https://github.com/hotcfg/cli) after checking its SHA-256 checksum, then runs one command. It works on Linux and macOS runners, x64 and arm64.

- **`validate`** checks a file against the bin's JSON Schema, on the runner, without changing anything.
- **`push`** publishes the file as the bin's next version.
- **`promote`** copies one environment's latest version to another.

Every error shows up as an annotation on the line of the file that caused it, right in the pull request.

## Quickstart

Add a secret API key (`sk_live_…`) as the repository secret `HOTCFG_API_KEY` (**Settings → Secrets and variables → Actions**), then add this workflow:

```yaml
# .github/workflows/config.yml
name: Config

on:
  pull_request:
    paths: [config/flags.json]
  push:
    branches: [main]
    paths: [config/flags.json]

permissions:
  contents: read

# One push at a time per branch, so versions land in order.
concurrency:
  group: config-${{ github.ref }}

jobs:
  config:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      # Pull requests from this repository: check the file against the bin's
      # schema. Nothing is published.
      - if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository
        uses: hotcfg/action@v1
        with:
          command: validate
          file: config/flags.json
          bin: acme/mobile-flags
          api-key: ${{ secrets.HOTCFG_API_KEY }}

      # Pull requests from forks get no secrets: check that the file is valid JSON.
      - if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository
        uses: hotcfg/action@v1
        with:
          command: validate
          file: config/flags.json

      # Merge to main: push to staging.
      - if: github.event_name == 'push'
        id: push
        uses: hotcfg/action@v1
        with:
          command: push
          file: config/flags.json
          bin: acme/mobile-flags
          environment: staging
          api-key: ${{ secrets.HOTCFG_API_KEY }}

      - if: github.event_name == 'push'
        env:
          VERSION: ${{ steps.push.outputs.version }}
        run: echo "staging is now v$VERSION"
```

When the file breaks the schema, the job fails and the pull request shows each error on its line:

```text
config/flags.json:3  /limits/max_upload_mb
  must be an integer, not a string
```

`push` checks the schema again: it is always the final check.

## Inputs

| Name | Description | Required | Default |
| --- | --- | --- | --- |
| `command` | `validate`, `push`, `promote` or `install` (see [Commands](#commands)). | No | `validate` |
| `api-key` | Secret API key, passed to the CLI as `HOTCFG_API_KEY`. Pass it from a secret. | For `push`, `promote`, and `validate` with `bin` | `""` |
| `bin` | The bin: an id, or `org-slug/id`. With `validate`, the file is also checked against its schema. | For `push`, `promote` | `""` |
| `file` | Path to the JSON file. | For `validate`, `push` | `""` |
| `environment` | `push`: the environment to write to. `promote`: the target environment. `development`, `staging` or `production`. | For `push`, `promote` | `""` |
| `from-environment` | `promote`: the source environment. | For `promote` | `""` |
| `version` | The CLI release to install, e.g. `v0.2.0`, or `latest`. At least `v0.2.0`. | No | `latest` |
| `api-url` | API base URL, for testing against another server. | No | `https://api.hotcfg.run` |
| `extra-args` | More CLI flags, split on whitespace (quotes are not interpreted). | No | `""` |

The action never picks an environment for you. The CLI writes to `production` when `--env` is left out; the action fails instead.

## Outputs

| Name | Description |
| --- | --- |
| `cli-version` | The CLI version installed, e.g. `v0.2.0`. |
| `version` | `push` and `promote`: the bin version just created in the target environment, as a number, e.g. `4`. |
| `hash` | `push` and `promote`: the content hash of that version. |
| `promoted-from-version` | `promote`: the version of the source environment that was copied. |

After `push` or `promote`, the action writes the new version to the job summary.

## Commands

| Command | What it runs | Needs a key |
| --- | --- | --- |
| `validate` | `hotcfg validate <file>`: the file must be one JSON value. With `bin`: `hotcfg validate <file> --bin <bin>`, which also checks it against the bin's schema, on the runner. | With `bin` |
| `push` | `hotcfg push <file> --bin <bin> --env <environment>` | Yes |
| `promote` | `hotcfg promote <bin> --from <from-environment> --to <environment>` | Yes |
| `install` | Only puts `hotcfg` on the `PATH`, for your own `run:` steps | No |

Every command installs the CLI, so later steps can call `hotcfg` directly, e.g. `hotcfg diff`, `hotcfg history` or `hotcfg rollback`. Set `HOTCFG_API_KEY` in those steps' `env:`.

## Promote from development to staging to production

Use one key per stage, each [limited](https://hotcfg.run/docs/reference/keys) to the bin and the environments it needs, and keep the production key in a GitHub [environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment) with required reviewers:

| Key | Environments | Stored in GitHub as |
| --- | --- | --- |
| CI | `development`, `staging` | Repository secret `HOTCFG_API_KEY` |
| Promote | `staging`, `production` | Secret `HOTCFG_API_KEY` of the `production` environment |

Run this workflow by hand from **Actions → Promote config → Run workflow**. Each job waits for the one before it, and the production job waits for a reviewer:

```yaml
# .github/workflows/promote.yml
name: Promote config

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  staging:
    runs-on: ubuntu-latest
    steps:
      - uses: hotcfg/action@v1
        with:
          command: promote
          bin: acme/mobile-flags
          from-environment: development
          environment: staging
          api-key: ${{ secrets.HOTCFG_API_KEY }}

  production:
    needs: staging
    runs-on: ubuntu-latest
    # Waits for a required reviewer, then gets the production environment's key.
    environment: production
    steps:
      - id: promote
        uses: hotcfg/action@v1
        with:
          command: promote
          bin: acme/mobile-flags
          from-environment: staging
          environment: production
          api-key: ${{ secrets.HOTCFG_API_KEY }}

      - env:
          TO: ${{ steps.promote.outputs.version }}
          FROM: ${{ steps.promote.outputs.promoted-from-version }}
        run: echo "production v$TO (from staging v$FROM)"
```

If the quickstart workflow already pushes to `staging` on merge, drop the `staging` job and promote only staging to production.

A promote is checked against the bin's schema too, and recorded in the bin's history with the key's name. To undo, roll back in the dashboard or run `hotcfg rollback acme/mobile-flags --env production --to <version>`.

## More examples

Pin the CLI so a new release never changes your build:

```yaml
- uses: hotcfg/action@v1
  with:
    version: v0.2.0
    command: push
    file: config/flags.json
    bin: acme/mobile-flags
    environment: staging
    api-key: ${{ secrets.HOTCFG_API_KEY }}
```

Write a diff of the new version to the job summary:

```yaml
- id: push
  uses: hotcfg/action@v1
  with:
    command: push
    file: config/flags.json
    bin: acme/mobile-flags
    environment: staging
    api-key: ${{ secrets.HOTCFG_API_KEY }}

- if: steps.push.outputs.version > 1
  env:
    HOTCFG_API_KEY: ${{ secrets.HOTCFG_API_KEY }}
    V: ${{ steps.push.outputs.version }}
  run: |
    {
      echo '```diff'
      hotcfg diff acme/mobile-flags --env staging --from "$((V - 1))" --to "$V"
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
```

Bundle production config into an app build as offline defaults:

```yaml
- uses: hotcfg/action@v1
  with:
    command: install
- run: hotcfg get acme/mobile-flags --env production > app/src/main/assets/flags.json
```

A public bin needs no key. For a private bin, pass a publishable key (`pk_live_…`) limited to that bin and `production`, and name the bin with its organization, as above:

```yaml
- run: hotcfg get acme/mobile-flags --env production > app/src/main/assets/flags.json
  env:
    HOTCFG_API_KEY: ${{ secrets.HOTCFG_READ_KEY }}
```

The CLI then reads the bin the way your app does, so a publish from the last 30 seconds may not be in it yet. Use a secret key instead if the build must have the very latest version. Reading with a publishable key needs CLI v0.4.1 or later, which `version: latest` (the default) installs.

## Security

- The API key reaches the CLI only through the `HOTCFG_API_KEY` environment variable. No input is put into a shell command directly, so input values can't inject commands.
- The CLI archive is checked against the release's `checksums.txt` before it runs, and the action stops on a mismatch.
- Text from your files (keys, values) is escaped before it's printed, so it can't pose as a workflow command.
- To lock the action itself, pin it to a commit SHA: `uses: hotcfg/action@<sha> # v1.0.0`.

More: the [CI guide](https://hotcfg.run/docs/guides/ci) and the [CLI reference](https://hotcfg.run/docs/cli).

## License

[Apache License 2.0](LICENSE)
