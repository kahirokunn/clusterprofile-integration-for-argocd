# Developing the Helm chart

The chart lives under
`install/helm-repo/argocd-clusterprofile-controller`.

## Chart version

Any change to chart templates, `values.yaml`, `values.schema.json`,
`Chart.yaml`, CRDs, tests, or generated chart docs must include a strictly
higher `version` in:

```text
install/helm-repo/argocd-clusterprofile-controller/Chart.yaml
```

`appVersion` tracks the controller image tag. The release init workflow updates
both `version` and `appVersion` for release branches.

## Local validation

Run:

```bash
make validate-values-schema
make generate-helm-docs
```

`make validate-values-schema` runs `helm lint` and verifies that every
`values.yaml` path is represented in `values.schema.json`.

`make generate-helm-docs` regenerates the chart README from chart metadata and
`values.yaml` comments.

