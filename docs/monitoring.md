# Monitoring

Operators use the controller's Prometheus endpoint to find invalid inventory
member labels, member ID conflicts, and successful changes to Argo CD cluster
Secrets. The same endpoint also includes the standard controller-runtime and
workqueue metrics.

## Metrics endpoint

The controller listens on `:8080` by default and serves metrics at `/metrics`.
The bundled Service is `argocd-clusterprofile-controller` in the `argocd`
namespace, so a direct check is:

```bash
kubectl -n argocd port-forward service/argocd-clusterprofile-controller 8080:8080
curl http://127.0.0.1:8080/metrics
```

The custom metrics are:

| Metric | Labels | What an operator can decide |
| --- | --- | --- |
| `argocd_clusterprofile_inventory_member_groups` | `namespace`, `resolution` | Count active non-empty member ID groups. `resolution` is `unique`, `duplicate`, or `ambiguous`. Use this for namespace-level inventory health. |
| `argocd_clusterprofile_inventory_member_conflict_group_size` | `namespace`, `inventory_member_id`, `resolution` | Count active ClusterProfiles in each `duplicate` or `ambiguous` member ID group. The series exists only for conflicts, which keeps healthy member IDs out of metric labels and identifies the member to repair. |
| `argocd_clusterprofile_inventory_member_id_invalid_profiles` | `namespace` | Count active ClusterProfiles whose `multicluster.x-k8s.io/inventory-member-id` label is present but empty. These profiles are not deduplicated. |
| `argocd_clusterprofile_secret_changes_total` | `namespace`, `operation`, `dry_run` | Count successful controller-issued `create`, `update`, and `delete` operations on Argo CD cluster Secrets. No-op reconciles, failed requests, already-missing Secrets, and Kubernetes garbage collection are not counted. |
| `argocd_clusterprofile_inventory_collection_errors_total` | none | Count failures to list ClusterProfiles from the controller cache while serving metrics. The last successful state snapshot remains visible after a failure. |

Terminating ClusterProfiles are excluded from the three inventory state gauges.
A namespace is an inventory boundary, so the same member ID in `argocd-prod`
and `argocd-dev` produces two independent groups.

### Queries with multiple controller replicas

Every replica reads the same Kubernetes state from its cache. Use `max` for
state gauges so identical replicas are not added together:

```promql
max by (namespace, inventory_member_id) (
  argocd_clusterprofile_inventory_member_conflict_group_size{resolution="duplicate"}
)
```

Operation counters are process-local. Sum their rates across replicas:

```promql
sum by (namespace, operation, dry_run) (
  rate(argocd_clusterprofile_secret_changes_total[5m])
)
```

## Prometheus Operator with Helm

The chart creates the metrics Service by default. To also create a
`ServiceMonitor` and the bundled warning alerts, install the Prometheus Operator
CRDs and use values such as:

```yaml
service:
  metrics:
    serviceMonitor:
      enabled: true
      additionalLabels:
        release: kube-prometheus-stack
    rules:
      enabled: true
      additionalLabels:
        release: kube-prometheus-stack
```

`release: kube-prometheus-stack` is a representative selector used by a
kube-prometheus-stack release. Set labels that match the `serviceMonitorSelector`
and `ruleSelector` of the Prometheus instance in your cluster. The three default
rules wait five minutes before warning about:

| Alert | Condition | Expected operator action |
| --- | --- | --- |
| `ClusterProfileInventoryMemberDuplicate` | One namespace has multiple ClusterProfiles with the same member ID and one uniquely oldest ClusterProfile. | Delete unintended newer duplicates after confirming that the uniquely oldest object should remain. |
| `ClusterProfileInventoryMemberAmbiguous` | Multiple ClusterProfiles with the same member ID share the oldest `creationTimestamp`, so none is selected. | Delete unintended duplicates until exactly one oldest object remains. The controller leaves existing generated Secrets unchanged while the tie exists. |
| `ClusterProfileInventoryMemberIDInvalid` | At least one active ClusterProfile has an empty member ID label. | Set a stable non-empty member ID or remove the label if the object must not participate in deduplication. |

Override `service.metrics.rules.spec` to replace the bundled rules. Prometheus,
Thanos Ruler, Mimir, or another Prometheus-compatible rule evaluator evaluates
the `PrometheusRule`; an OpenTelemetry Collector does not evaluate it.

## Kustomize monitoring overlay

The default `artifacts/manifests` installation does not contain Prometheus
Operator resources. If those CRDs are installed, deploy the controller,
`ServiceMonitor`, and `PrometheusRule` together with:

```bash
kubectl apply -k artifacts/overlays/monitoring
```

The overlay uses the `argocd` namespace and has no installation-specific
Prometheus discovery label. If the Prometheus instance selects resources using
a label such as `release: kube-prometheus-stack`, add that label to both
`service-monitor.yaml` and `prometheus-rule.yaml` in a site-specific overlay.

## OpenTelemetry Collector

The controller does not export OTLP. An OpenTelemetry Collector can ingest its
Prometheus endpoint with a Prometheus receiver. For a single replica, scrape
`argocd-clusterprofile-controller.argocd.svc.cluster.local:8080`; for multiple
replicas, discover Pod endpoints rather than scraping the load-balanced Service.
