# argocd-clusterprofile-controller

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: main](https://img.shields.io/badge/AppVersion-main-informational?style=flat-square)

Argo CD ClusterProfile controller for registering ClusterProfile resources as Argo CD clusters

**Homepage:** <https://github.com/argoproj-labs/clusterprofile-integration-for-argocd>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Argo Project Maintainers |  | <https://github.com/argoproj-labs/clusterprofile-integration-for-argocd> |

## Source Code

* <https://github.com/argoproj-labs/clusterprofile-integration-for-argocd>

## Requirements

Kubernetes: `>=1.26.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for the controller pod. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Container-level security context. |
| controller.argoCDCmdParams.configMapName | string | `"argocd-cmd-params-cm"` | ConfigMap name containing Argo CD command parameters. |
| controller.argoCDCmdParams.enabled | bool | `true` | Read optional Argo CD command parameter keys from a ConfigMap. |
| controller.args | list | `[]` | Extra command-line arguments appended after the chart-managed arguments. |
| controller.clusterProfileNamespaces | list | `[]` | Namespaces to watch for ClusterProfile resources. Empty means the release namespace. Use `*` alone to watch all namespaces. When `rbac.create` is true, matching ClusterProfile RBAC is generated. |
| controller.clusterProfileProvidersFile | string | `""` | Path to a mounted ClusterProfile providers file. |
| controller.debug | bool | `false` | Enable debug logging. Takes precedence over logLevel. |
| controller.dryRun | bool | `false` | Enable dry-run mode. |
| controller.enableLeaderElection | bool | `false` | Enable controller-runtime leader election. |
| controller.extraEnv | list | `[]` | Extra environment variables for the controller container. |
| controller.extraEnvFrom | list | `[]` | Extra envFrom entries for the controller container. |
| controller.extraVolumeMounts | list | `[]` | Extra volume mounts for the controller container. |
| controller.extraVolumes | list | `[]` | Extra volumes for the controller pod. |
| controller.logFormat | string | `""` | Explicit log format (`json` or `text`). Empty keeps the controller default or Argo CD cmd params value. |
| controller.logLevel | string | `""` | Explicit log level (`debug`, `info`, `warn`, `error`). Empty keeps the controller default or Argo CD cmd params value. |
| controller.metricsAddr | string | `":8080"` | Metrics bind address passed to the controller. |
| controller.name | string | `"clusterprofile-controller"` | Controller name string used as the component name and appended to the base fullname. |
| controller.probePort | int | `8081` | Health probe container port. |
| fullnameOverride | string | `""` | String to fully override the base fully-qualified resource name. |
| global | object | `{}` | Global values reserved for parent charts. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy for the controller container. |
| image.repository | string | `"ghcr.io/argoproj-labs/clusterprofile-integration-for-argocd"` | Container image repository for the controller. |
| image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| imagePullSecrets | list | `[]` | Image pull secrets for the controller pod. |
| nameOverride | string | `"argocd"` | Provide a name in place of `argocd`. |
| namespaceOverride | string | `""` | Override the Kubernetes namespace used in rendered namespaced resources. |
| networkPolicy.enabled | bool | `true` | Create a NetworkPolicy allowing access to the metrics port. |
| networkPolicy.ingress.namespaceSelector | object | `{}` | Namespace selector allowed to access the metrics port. |
| nodeSelector | object | `{"kubernetes.io/os":"linux"}` | Node selector for the controller pod. |
| podAnnotations | object | `{}` | Extra annotations for the controller pods. |
| podLabels | object | `{}` | Extra labels for the controller pods. |
| podSecurityContext | object | `{}` | Pod-level security context. |
| priorityClassName | string | `""` | Priority class name for the controller pod. |
| rbac.create | bool | `true` | Create namespaced RBAC resources for the controller. |
| replicaCount | int | `1` | Number of controller replicas. |
| resources | object | `{}` | Resource requests and limits for the controller container. |
| service.metrics.annotations | object | `{}` | Extra annotations for the metrics Service. |
| service.metrics.enabled | bool | `true` | Create a metrics Service. |
| service.metrics.port | int | `8080` | Metrics Service port. |
| service.metrics.type | string | `"ClusterIP"` | Metrics Service type. |
| serviceAccount.annotations | object | `{}` | Extra annotations for the service account. |
| serviceAccount.create | bool | `true` | Create a service account for the controller. |
| serviceAccount.labels | object | `{}` | Extra labels for the service account. |
| serviceAccount.name | string | `"argocd-clusterprofile-controller"` | Controller service account name. |
| tolerations | list | `[]` | Tolerations for the controller pod. |
| topologySpreadConstraints | list | `[]` | Topology spread constraints for the controller pod. |
