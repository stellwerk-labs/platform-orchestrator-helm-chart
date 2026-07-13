# spicedb

A Helm chart for creating SpiceDB cluster for Platform Orchestrator

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `true` | Enable SpiceDB |
| initContainer | object | `{"image":"bitnami/kubectl:latest"}` | Init container configuration for creating the secret |
| initContainer.image | string | `"bitnami/kubectl:latest"` | kubectl image used by the init container |
| patches | list | `[]` | Strategic merge patches applied to SpiceDB resources Use this to inject sidecars (e.g., cloud-sql-proxy), add annotations, etc. Example (CloudSQL proxy sidecar):  - kind: Deployment    patch:      spec:        template:          spec:            initContainers:              - args:                  - --structured-logs                  - --port=5432                  - --auto-iam-authn                  - <cloudsql-instance-connection-name>                image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.1                name: cloud-sql-proxy            restartPolicy: Always            securityContext:              runAsNonRoot: true  - kind: Job    patch:      spec:        template:          spec:            initContainers:              - args:                  - --structured-logs                  - --port=5432                  - --auto-iam-authn                  - <cloudsql-instance-connection-name>                image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.1                name: cloud-sql-proxy                restartPolicy: Always                securityContext:                  runAsNonRoot: true  - kind: ServiceAccount    patch:      metadata:        annotations:          iam.gke.io/gcp-service-account: <gcp service account> |
| replicas | int | `1` | Number of SpiceDB replicas |
| secretName | string | `"spicedb-cluster-config"` | Name of the secret containing the SpiceDB cluster config (preshared key) |
