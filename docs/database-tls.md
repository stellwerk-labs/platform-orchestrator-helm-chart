# Database TLS

Control Plane, Data Plane and IAM read `DATABASE_SSLMODE` when they start.
The default is `disable`, preserving existing installations.
Use the corresponding Core release that implements this setting; older images ignore the new variable and keep their previous behavior.
The chart image pins must be updated to those qualified images before this chart change is released.

## Require encryption

Set the mode for each Core component:

```yaml
control-plane:
  config:
    DATABASE_SSLMODE: require
data-plane:
  config:
    DATABASE_SSLMODE: require
iam:
  config:
    DATABASE_SSLMODE: require
```

The PostgreSQL server must accept TLS connections.
`require` refuses a server without TLS; it does not fall back to plaintext.
It does not generally authenticate the server identity, so use `verify-full` when you need certificate and hostname verification.
The existing PostgreSQL driver also supports `allow`, `prefer` and `verify-ca`; `allow` and `prefer` permit plaintext and do not provide the guarantee of `require`.
Invalid modes fail during database initialization.
Apply the Helm values and restart the components to establish new database connections.

## Verify the server certificate

Provision a Kubernetes Secret containing the database CA certificate, then reuse the existing backend Secret-file profile.
For example, configure the Control Plane as follows:

```yaml
control-plane:
  config:
    DATABASE_SSLMODE: verify-full
  configurationProfiles:
    databaseTLS:
      enabled: true
      config:
        PGSSLROOTCERT: /etc/stellwerk/database/ca.crt
      secretFiles:
        - name: database-ca
          secretName: database-ca
          key: ca.crt
          mountPath: /etc/stellwerk/database/ca.crt
```

Use the same profile under `data-plane` and `iam` for their connections.
The `DATABASE_HOST` must match the server certificate, and each component must trust its database server's CA.
`verify-ca` checks the certificate chain; `verify-full` also checks the hostname.
The chart references existing Secrets and does not create, issue or rotate certificates.

The IAM authorization migration command already supports `DATABASE_SSLMODE` when constructing its connection string.
An explicit `--database-url` or `DATABASE_URL` remains authoritative, including its own TLS parameters.
Private plugins accept operator-supplied database URLs; include the appropriate `sslmode` in those URLs.

For PostgreSQL mode semantics, see the [PostgreSQL SSL documentation](https://www.postgresql.org/docs/current/libpq-ssl.html).
