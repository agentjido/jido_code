# Self-Hosted Provider Auth Guide

<!-- covers: docs.operator_provider_auth_guide.github_broker_registration_steps -->
<!-- covers: docs.operator_provider_auth_guide.github_service_credential_setup -->
<!-- covers: docs.operator_provider_auth_guide.callback_and_allowlist_explained -->
<!-- covers: docs.operator_provider_auth_guide.future_provider_notes -->

This guide is for operators running `jido_code` in a self-hosted deployment.

The current model has two separate authentication and integration concerns:

- `Provider Login`: broker-managed browser sign-in for humans.
- `Git Provider Integrations`: deployment-local credentials for automation, webhooks, and repository access checks.

Do not reuse one for the other. Broker trust fields belong to provider login. GitHub App, PAT, and webhook secrets belong to deployment-local service integration.

## What Exists Today

- Local email authentication is the fallback path and remains enabled.
- The landing page exposes `Sign In with GitHub` when GitHub provider login is enabled for `github.com`.
- The authenticated landing page exposes separate `Provider Login` and `Git Provider Integrations` sections.
- GitHub service integration is implemented.
- GitLab and Bitbucket are modeled in the provider catalog, but service adapters remain placeholders.

## Operator Setup Order

1. Start with local email auth and bootstrap the first operator account.
2. Configure broker-managed GitHub login.
3. Configure deployment-local GitHub automation credentials.
4. Verify provider login and GitHub service readiness separately on the landing page.

## Provider Login Architecture

`jido_code` is not the OAuth callback service. The deployment redirects the browser to an external auth broker, and the broker returns a signed handoff back to the deployment.

Current deployment contract:

- Start endpoint: `/auth/providers/github/start`
- Complete endpoint: `/auth/providers/github/complete`

Current browser flow:

1. The user clicks `Sign In with GitHub`.
2. The deployment start endpoint signs state and redirects to the broker start URL.
3. The broker handles GitHub authentication.
4. The broker redirects back to the deployment complete endpoint with `state` and `handoff_token`.
5. The deployment validates broker trust, evaluates allowlists, links or provisions the local user, and issues the normal local session.

## GitHub Login App Registration

This repo assumes a broker-managed GitHub login app with a fixed public callback on the broker, not a per-deployment callback on each `jido_code` install.

Recommended broker convention:

- Broker base URL: `https://auth.example.com`
- Broker start URL: `https://auth.example.com/auth/providers/github/start`
- Broker callback URL: `https://auth.example.com/auth/providers/github/callback`

Recommended GitHub App registration fields:

- GitHub App name: `Jido Code Auth Broker`
- Homepage URL: `https://auth.example.com`
- Callback URL: `https://auth.example.com/auth/providers/github/callback`
- User authorization: enabled

After the broker app exists, configure the `jido_code` deployment with these broker trust values in the `Provider Login` section for GitHub:

- Provider host: `github.com`
- Broker base URL: `https://auth.example.com`
- Broker issuer: `https://auth.example.com`
- Broker audience: `jido-code`

The deployment then generates the per-install completion URL automatically when it calls the broker start endpoint. That is why the GitHub App callback belongs to the broker and stays fixed.

## Provider Login Settings

The `Provider Login` section manages these fields per provider host:

- `Enable provider host`
- `Allow browser sign-in`
- `Allowlist mode`
- `Allowlist values`
- `Broker base URL`
- `Broker issuer`
- `Broker audience`

Readiness rules:

- Provider host must be enabled.
- Browser sign-in must be enabled.
- Broker base URL, issuer, and audience must be present.
- If allowlist mode is not `none`, at least one allowlist value must be present.

Supported allowlist modes:

- `none`
- `users`
- `organizations`
- `teams`
- `groups`
- `workspaces`

Allowlist values can be entered one per line or comma-separated.

Allowlists are enforced before local user linking or account creation.

## Deployment-Local GitHub Service Credentials

GitHub automation does not read provider-login broker fields. Configure it separately.

Preferred GitHub automation path:

- GitHub App ID
- GitHub App private key
- GitHub App installation token

Optional fallback:

- GitHub PAT

Canonical SecretRef names:

- `vcs/github/app_id`
- `vcs/github/app_private_key`
- `vcs/github/webhook_secret`
- `vcs/github/pat`

Supported deployment-local env vars:

- `GITHUB_APP_ID`
- `GITHUB_APP_PRIVATE_KEY`
- `GITHUB_APP_INSTALLATION_TOKEN`
- `GITHUB_APP_ACCESSIBLE_REPOS`
- `GITHUB_APP_EXPECTED_REPOS`
- `GITHUB_PAT`
- `GITHUB_PAT_ACCESSIBLE_REPOS`
- `GITHUB_WEBHOOK_SECRET`

Service validation behavior:

- GitHub App is preferred ahead of PAT fallback.
- If `GITHUB_APP_ACCESSIBLE_REPOS` is present, the deployment uses it directly for readiness.
- If expected repos are configured and missing from the accessible set, readiness is blocked.
- PAT is optional and only used as fallback.

## Minimum GitHub Service Setup

For a minimal self-hosted test deployment, set:

```bash
export GITHUB_APP_ID="1234"
export GITHUB_APP_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----..."
export GITHUB_APP_INSTALLATION_TOKEN="ghs_example_installation_token"
export GITHUB_APP_ACCESSIBLE_REPOS="agentjido/jido_code"
```

If you want explicit repository expectations, also set:

```bash
export GITHUB_APP_EXPECTED_REPOS="agentjido/jido_code"
```

If you want PAT fallback, additionally set:

```bash
export GITHUB_PAT="ghp_example_personal_access_token"
export GITHUB_PAT_ACCESSIBLE_REPOS="agentjido/jido_code"
```

## What To Verify On The Landing Page

As an operator, after signing in locally you should verify two different things:

`Provider Login`

- GitHub card is `Ready`
- Broker base URL, issuer, and audience are present
- Allowlist mode and values match your intended policy

`Git Provider Integrations`

- GitHub integration summary is `Ready` or clearly explains why it is blocked
- `GitHub App` path shows repository access status
- Secret refs are listed separately from provider-login configuration

These sections are intentionally separate. A green GitHub automation status does not enable browser login, and a green browser-login status does not prove GitHub automation is configured.

## Callback, Redirect, And Allowlist Notes

Important distinctions:

- GitHub callback URL: fixed on the broker
- Deployment complete URL: generated by `jido_code` and passed to the broker as `redirect_uri`
- Signed deployment state: generated by `jido_code`
- Broker handoff token: generated by the broker

Allowlist consequences:

- A rejected provider identity does not get a local browser session.
- A rejected provider identity does not break deployment-local GitHub automation readiness.
- Local email sign-in remains available even if provider login is rejected or the broker is unavailable.

## Future Providers

Current status:

- `GitLab`: provider config and identity model exist; landing-page browser entrypoint is not exposed; service adapter is a placeholder.
- `Bitbucket`: provider config and identity model exist; landing-page browser entrypoint is not exposed; service adapter is a placeholder.

What that means operationally:

- You can plan around a shared provider model now.
- You should only expect GitHub end-to-end behavior in this phase.
- GitLab and Bitbucket will need later provider-specific broker and service-integration work before they are operator-ready.
