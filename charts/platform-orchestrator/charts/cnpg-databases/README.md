# cnpg-databases

CloudNativePG cluster with databases for Platform Orchestrator

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| admin | object | `{"passwordSecretKey":"password","passwordSecretName":"postgres-admin-secret","username":"postgres"}` | Initial admin/superuser credentials |
| admin.passwordSecretKey | string | `"password"` | Key within the secret containing the password |
| admin.passwordSecretName | string | `"postgres-admin-secret"` | Secret name containing the superuser password |
| admin.username | string | `"postgres"` | Superuser username |
| cluster | object | `{"instances":1,"storageClass":"standard","storageSize":"1Gi"}` | Cluster settings |
| cluster.instances | int | `1` | Number of PostgreSQL instances |
| cluster.storageClass | string | `"standard"` | Storage class name |
| cluster.storageSize | string | `"1Gi"` | PVC storage size per instance |
| databases | list | `[{"name":"orchestrator-controlplane","owner":"controlplane_user","passwordSecretKey":"password","passwordSecretName":"controlplane-db-secret"},{"name":"orchestrator-dataplane","owner":"dataplane_user","passwordSecretKey":"password","passwordSecretName":"dataplane-db-secret"},{"name":"orchestrator-iam","owner":"iam_user","passwordSecretKey":"password","passwordSecretName":"iam-db-secret"}]` | List of databases to create |
| enabled | bool | `true` | Enable the PostgreSQL cluster |
| postgresql | object | `{"logStatement":"all","maxConnections":"100","sharedBuffers":"256MB"}` | PostgreSQL server parameters |
| postgresql.logStatement | string | `"all"` | Statement logging level (none, ddl, mod, all) |
| postgresql.maxConnections | string | `"100"` | Maximum number of concurrent connections |
| postgresql.sharedBuffers | string | `"256MB"` | Shared buffer size |
