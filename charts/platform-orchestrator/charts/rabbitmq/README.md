# rabbitmq

A Helm chart for creating RabbitMQ cluster for Platform Orchestrator

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalConfig | string | `"cluster_partition_handling = pause_minority\nvm_memory_high_watermark_paging_ratio = 0.99\ndisk_free_limit.absolute = 50MB\ncollect_statistics_interval = 10000\n"` | Additional RabbitMQ configuration (rabbitmq.conf format) disk_free_limit.absolute is set to 50MB instead of relative=1.0 because the chart ships persistence.storage: 1Gi but the resource limit memory is 4Gi. A relative=1.0 threshold would demand ~4Gi free disk and fire the alarm permanently, TCP-blocking every publisher. Override the default if you size the PVC larger. |
| affinity | object | `{}` | Pod affinity rules |
| enabled | bool | `true` | Enable the RabbitMQ cluster |
| image | object | `{"repository":"rabbitmq","tag":"3.12-management"}` | Container image configuration |
| image.repository | string | `"rabbitmq"` | Image repository |
| image.tag | string | `"3.12-management"` | Image tag |
| override | object | `{"annotations":{},"topologySpreadConstraints":[]}` | RabbitmqCluster spec overrides |
| override.annotations | object | `{}` | Additional annotations on the RabbitmqCluster resource  Example (Datadog integration):  annotations:    ad.datadoghq.com/rabbitmq.checks: |      {        "rabbitmq": {          "init_config": {},          "instances": [{            "rabbitmq_api_url":"http://%%host%%:15672/api/",            "username": "datadog",            "password": "%%env_RABBITMQ_USER_DATADOG_PASSWORD%%"          }]        }      } |
| override.topologySpreadConstraints | list | `[]` | Topology spread constraints |
| persistence | object | `{"storage":"1Gi","storageClassName":"standard"}` | Persistence configuration |
| persistence.storage | string | `"1Gi"` | PVC storage size |
| persistence.storageClassName | string | `"standard"` | Storage class name |
| replicas | int | `1` | Number of RabbitMQ replicas |
| resources | object | `{"limits":{"cpu":"2","memory":"4Gi"},"requests":{"cpu":"500m","memory":"2Gi"}}` | CPU/memory resource requests and limits |
| vhost | object | `{"name":"platform"}` | Virtual host configuration |
| vhost.name | string | `"platform"` | Virtual host name |
