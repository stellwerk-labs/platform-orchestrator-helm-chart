# seaweed

Seaweed Storage for Platform Orchestrator

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `true` | Enable SeaweedFS |
| filer | object | `{"config":"[leveldb2]\nenabled = true\ndir = \"/data/filerdb2\"\n","iam":true,"limits":{"cpu":"1000m","memory":"512Mi"},"persistence":{"accessModes":["ReadWriteOnce"],"enabled":false,"mountPath":"/data","requests":{"storage":"4Gi"},"storageClassName":"gp2"},"replicas":1,"requests":{"cpu":"200m","memory":"256Mi"},"s3":{"configSecret":{"key":"config","name":"s3-secret"}}}` | Filer component configuration |
| filer.config | string | `"[leveldb2]\nenabled = true\ndir = \"/data/filerdb2\"\n"` | Custom filer.toml configuration |
| filer.iam | bool | `true` | Enable IAM for S3 authentication |
| filer.limits | object | `{"cpu":"1000m","memory":"512Mi"}` | CPU/memory limits for filer |
| filer.persistence | object | `{"accessModes":["ReadWriteOnce"],"enabled":false,"mountPath":"/data","requests":{"storage":"4Gi"},"storageClassName":"gp2"}` | Filer persistence settings |
| filer.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the PVC |
| filer.persistence.enabled | bool | `false` | Enable persistent storage for the filer |
| filer.persistence.mountPath | string | `"/data"` | Mount path for persistent storage |
| filer.persistence.requests | object | `{"storage":"4Gi"}` | Storage requests |
| filer.persistence.requests.storage | string | `"4Gi"` | PVC storage size |
| filer.persistence.storageClassName | string | `"gp2"` | Storage class name |
| filer.replicas | int | `1` | Number of filer replicas |
| filer.requests | object | `{"cpu":"200m","memory":"256Mi"}` | CPU/memory requests for filer |
| filer.s3 | object | `{"configSecret":{"key":"config","name":"s3-secret"}}` | S3 settings within filer |
| filer.s3.configSecret.key | string | `"config"` | Key within the secret |
| filer.s3.configSecret.name | string | `"s3-secret"` | Secret name containing the S3 configuration |
| image | object | `{"pullPolicy":"Always","repository":"chrislusf/seaweedfs","tag":"latest"}` | Global image settings |
| image.pullPolicy | string | `"Always"` | Image pull policy |
| image.repository | string | `"chrislusf/seaweedfs"` | Image repository |
| image.tag | string | `"latest"` | Image tag |
| master | object | `{"concurrentStart":false,"garbageThreshold":"0.3","limits":{"cpu":"200m","memory":"256Mi"},"replicas":1,"requests":{"cpu":"100m","memory":"128Mi"},"volumeSizeLimitMB":30000}` | Master server configuration |
| master.concurrentStart | bool | `false` | Whether to start masters concurrently |
| master.garbageThreshold | string | `"0.3"` | Garbage collection threshold (fraction of wasted space to trigger GC) |
| master.limits | object | `{"cpu":"200m","memory":"256Mi"}` | CPU/memory limits for master |
| master.replicas | int | `1` | Number of master replicas |
| master.requests | object | `{"cpu":"100m","memory":"128Mi"}` | CPU request for master |
| master.volumeSizeLimitMB | int | `30000` | Maximum volume size in MB |
| volume | object | `{"dataCenter":"DefaultDataCenter","port":8080,"rack":"DefaultRack","replicas":1,"resources":{"limits":{"cpu":"400m","memory":"512Mi"},"requests":{"cpu":"200m","memory":"256Mi"}},"storage":"50Gi"}` | Volume server configuration |
| volume.dataCenter | string | `"DefaultDataCenter"` | Data center name (required by SeaweedFS CRD) |
| volume.port | int | `8080` | Volume server port |
| volume.rack | string | `"DefaultRack"` | Rack name (required by SeaweedFS CRD) |
| volume.replicas | int | `1` | Number of volume server replicas |
| volume.resources | object | `{"limits":{"cpu":"400m","memory":"512Mi"},"requests":{"cpu":"200m","memory":"256Mi"}}` | CPU/memory resource requests and limits for volume server |
| volume.storage | string | `"50Gi"` | Volume server storage size |
