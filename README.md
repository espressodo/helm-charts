# Espresso Data Privacy Helm Charts

Official Helm charts for espressodo projects.

## Usage

The charts can be added using the following command:

```bash
helm repo add espressodo https://espressodo.github.io/helm-charts/
helm repo update
```

## TLS trust bundles for PostgreSQL and Temporal

Chart version `0.1.7` adds optional runtime-mounted CA trust bundles for PostgreSQL and Temporal. This keeps Espresso images customer-neutral: customer-specific root CAs are provided by Kubernetes Secrets at deployment time.

Create the CA Secrets in the release namespace, for example:

```bash
kubectl create secret generic espresso-postgres-ca --from-file=ca.crt=./postgres-ca.crt
kubectl create secret generic espresso-temporal-ca --from-file=ca.crt=./temporal-ca.crt
```

Enable PostgreSQL certificate verification:

```yaml
db:
  postgres:
    sslMode: verify-full
    sslRootCert:
      enabled: true
      existingSecret: espresso-postgres-ca
      secretKey: ca.crt
      mountPath: /etc/espresso/postgres-trust
      fileName: ca.crt
```

Enable Temporal TLS:

```yaml
temporal:
  tls:
    enabled: true
    serverName: temporal.example.internal
    ca:
      existingSecret: espresso-temporal-ca
      secretKey: ca.crt
      mountPath: /etc/espresso/trust
      fileName: ca.crt
```

When enabled, the chart mounts the CA material into Engine, API, Backend, and Init Job pods. The frontend pod is not changed because it does not connect directly to PostgreSQL or Temporal.

## Gateway API parentRefs and explicit backendRefs

Chart version `0.1.8` renders `HTTPRoute.spec.parentRefs` from `gateway.parentRefs` when provided, instead of forcing a single hardcoded parentRef. The old `gateway.name`, `gateway.namespace`, and `gateway.sectionName` values remain supported as a backwards-compatible fallback when `gateway.parentRefs` is empty.

Example with an explicit parentRefs array:

```yaml
gateway:
  enabled: true
  host: espresso-dev.example.internal
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: customer-shared-gateway
      namespace: infra-gateway
      sectionName: http
```

The HTTPRoute backend references are now rendered explicitly with `group: ""`, `kind: Service`, `port`, and `weight: 1`.

## Temporal in a separate Kubernetes namespace

When Temporal runs in a different Kubernetes namespace than Espresso, set `temporal.kubernetesNamespace`. If `temporal.host` is a short Service name, the chart renders `TEMPORAL_HOST` as `<service>.<namespace>.svc`.

Example:

```yaml
temporal:
  host: temporal-frontend
  kubernetesNamespace: temporal
  port: 7233
```

This renders Espresso's Temporal endpoint as `temporal-frontend.temporal.svc:7233`. If you already provide a fully qualified DNS name in `temporal.host`, leave `temporal.kubernetesNamespace` empty or keep the full host; the chart will not rewrite hosts that already contain a dot.

## Espresso database migration 1.6.0 -> 1.7.0

Chart version `0.1.10` adds a GitOps/Helm-managed PostgreSQL migration job for the Espresso application upgrade from `1.6.0` to `1.7.0`.

The migration runs as a `pre-upgrade` Helm hook before the Espresso application pods are updated. The job is rendered only for upgrade runs when `dbMigration.enabled=true`, `dbMigration.fromVersion=1.6.0`, and `dbMigration.targetVersion=1.7.0`.

The migration applies the following idempotent change:

- creates the partial unique index `uq_user_externalid` on `espresso."user"(externalid)` for non-empty external IDs

Example values:

```yaml
dbMigration:
  enabled: true
  fromVersion: "1.6.0"
  targetVersion: "1.7.0"
  image:
    repository: postgres
    tag: "16-alpine"
    pullPolicy: IfNotPresent
```

If your GitOps controller needs explicit Argo CD hook annotations instead of Helm hook mapping, use:

```yaml
dbMigration:
  extraAnnotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-10"
```

The PostgreSQL role used by the chart must be allowed to create indexes in the `espresso` schema. If duplicate non-empty `externalid` values already exist in `espresso."user"`, PostgreSQL will reject the unique index creation and the migration job will fail until the duplicate data is cleaned up.

## ExternalSecret support

Chart version `0.1.11` adds optional support for the External Secrets Operator.
When `externalSecret.enabled=true`, the chart renders an `ExternalSecret` resource. The External Secrets Operator then creates the Kubernetes Secret referenced by the existing chart values such as `db.postgres.existingSecret` and `espresso.uiBackend.existingSecret`.

The chart does not install the External Secrets Operator or its CRDs. They must already exist in the target cluster.

Example:

```yaml
externalSecret:
  enabled: true
  refreshInterval: "1h0m0s"
  secretStoreRef:
    name: customer-secret-store
    kind: ClusterSecretStore
  targetSecretName: espresso-secrets
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: espresso/postgres
        property: password
    - secretKey: ESPRESSO_UI_API_PASSWORD_SALT
      remoteRef:
        key: espresso/ui-backend
        property: passwordSalt
    - secretKey: ESPRESSO_UI_API_PRIVATE_KEY
      remoteRef:
        key: espresso/ui-backend
        property: privateKey
```

Reference the generated Kubernetes Secret with the normal chart values:

```yaml
db:
  postgres:
    existingSecret: espresso-secrets
    passwordSecretKey: POSTGRES_PASSWORD

espresso:
  uiBackend:
    existingSecret: espresso-secrets
    passwordSaltSecretKey: ESPRESSO_UI_API_PASSWORD_SALT
    privateKeySecretKey: ESPRESSO_UI_API_PRIVATE_KEY
```

`externalSecret.dataFrom` is also supported for importing complete remote secret objects.

## PostgreSQL init tenant placeholder

Chart version `0.1.11` also fixes the PostgreSQL init job tenant placeholder mapping. The DB init container now receives `TENANT_CODE` from `espresso.tenant`, because the shipped SQL templates replace `#{TENANT_CODE}`.

Temporal namespace initialization is unchanged and still uses the Helm value `espresso.tenant` directly.

## OIDC 1.7 configuration

Chart version `0.1.12` adds the OIDC configuration parameters introduced for Espresso `1.7.0`.

Supported login modes are:

- `manual`: local/manual login
- `oidc`: OIDC login with an existing local/SCIM-provisioned user
- `sso`: legacy alias for `oidc`
- `oidc-only`: OIDC login with JIT user provisioning, without SCIM

Default OIDC flow and claim mapping values:

```yaml
espresso:
  uiBackend:
    loginMode: "oidc-only"

  sso:
    enabled: true
    authorityUrl: "https://idp.example.ch/oidc"
    clientId: "espresso-webapp"
    existingSecret: "espresso-secrets"
    clientSecretSecretKey: "AUTHORITY_CLIENT_SECRET"
    redirectUri: "https://espresso.example.ch/callback"
    postLogoutRedirectUri: "https://espresso.example.ch"
    scope: "openid profile email"

    discoveryEnabled: true
    requireState: true
    idTokenValidationRequired: true
    introspectionEnabled: false

    userIdClaim: "userid"
    emailClaim: "email"
    nameClaim: "name"
    roleClaim: "role"
    tenantClaim: "tenant"

    allowedRoles: "sysadmin,admin,operator,approver,observer"
    linkExistingUserByUserid: false
```

For customer-specific IdP mappings, override the claim names. Example for using the OIDC subject as Espresso userid:

```yaml
espresso:
  uiBackend:
    loginMode: "oidc"

  sso:
    enabled: true
    userIdClaim: "sub"
```

Optional explicit endpoint overrides are supported. When set, they override discovery and the legacy `AUTHORITY_URL` fallback:

```yaml
espresso:
  sso:
    authorizationEndpoint: "https://idp.example.ch/oauth2/authorize"
    tokenEndpoint: "https://idp.example.ch/oauth2/token"
    introspectionEndpoint: "https://idp.example.ch/oauth2/introspect"
    userInfoEndpoint: "https://idp.example.ch/oauth2/userinfo"
    jwksEndpoint: "https://idp.example.ch/oauth2/jwks"
    endSessionEndpoint: "https://idp.example.ch/oauth2/logout"
    issuer: "https://idp.example.ch/oidc"
```
