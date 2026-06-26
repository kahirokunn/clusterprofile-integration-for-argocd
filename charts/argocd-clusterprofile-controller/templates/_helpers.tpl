{{/*
Expand the name of the chart.
*/}}
{{- define "argocd-clusterprofile-controller.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "argocd-clusterprofile-controller.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create controller name and version as used by Kubernetes resources.
*/}}
{{- define "argocd-clusterprofile-controller.controller.fullname" -}}
{{- printf "%s-%s" (include "argocd-clusterprofile-controller.fullname" .) .Values.controller.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create controller name as used by app labels.
*/}}
{{- define "argocd-clusterprofile-controller.controller.name" -}}
{{- printf "%s-%s" (include "argocd-clusterprofile-controller.name" .) .Values.controller.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Expand the namespace of the release.
*/}}
{{- define "argocd-clusterprofile-controller.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "argocd-clusterprofile-controller.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "argocd-clusterprofile-controller.selectorLabels" -}}
app.kubernetes.io/name: {{ include "argocd-clusterprofile-controller.controller.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: {{ .Values.controller.name }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "argocd-clusterprofile-controller.labels" -}}
helm.sh/chart: {{ include "argocd-clusterprofile-controller.chart" . }}
{{ include "argocd-clusterprofile-controller.selectorLabels" . }}
app.kubernetes.io/part-of: argocd
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "argocd-clusterprofile-controller.serviceAccountName" -}}
{{- .Values.serviceAccount.name }}
{{- end }}

{{/*
Argo CD command params ConfigMap name.
*/}}
{{- define "argocd-clusterprofile-controller.cmdParamsConfigMapName" -}}
{{- .Values.controller.argoCDCmdParams.configMapName }}
{{- end }}

{{/*
Metrics port from controller.metricsAddr.
*/}}
{{- define "argocd-clusterprofile-controller.metricsPort" -}}
{{- splitList ":" .Values.controller.metricsAddr | last }}
{{- end }}

{{/*
Health probe port.
*/}}
{{- define "argocd-clusterprofile-controller.probePort" -}}
{{- .Values.controller.probePort }}
{{- end }}

{{/*
ClusterProfile namespaces argument passed to the controller.
*/}}
{{- define "argocd-clusterprofile-controller.clusterProfileNamespacesArg" -}}
{{- $namespaces := include "argocd-clusterprofile-controller.clusterProfileNamespaces" . | fromJsonArray -}}
{{- if $namespaces -}}{{ join "," $namespaces }}{{- else -}}{{ include "argocd-clusterprofile-controller.namespace" . }}{{- end -}}
{{- end }}

{{/*
Normalized ClusterProfile namespaces requested by the controller.
*/}}
{{- define "argocd-clusterprofile-controller.clusterProfileNamespaces" -}}
{{- $namespaces := list -}}
{{- range $namespace := default (list) .Values.controller.clusterProfileNamespaces -}}
{{- $namespace = trim $namespace -}}
{{- if $namespace -}}
{{- $namespaces = append $namespaces $namespace -}}
{{- end -}}
{{- end -}}
{{- toJson ($namespaces | uniq) -}}
{{- end }}

{{/*
Whether the controller watches ClusterProfiles in every namespace.
*/}}
{{- define "argocd-clusterprofile-controller.watchesAllClusterProfiles" -}}
{{- $namespaces := include "argocd-clusterprofile-controller.clusterProfileNamespaces" . | fromJsonArray -}}
{{- if has "*" $namespaces -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Whether the controller watches ClusterProfiles in the release namespace.
*/}}
{{- define "argocd-clusterprofile-controller.watchesReleaseNamespace" -}}
{{- $namespaces := include "argocd-clusterprofile-controller.clusterProfileNamespaces" . | fromJsonArray -}}
{{- $releaseNamespace := include "argocd-clusterprofile-controller.namespace" . -}}
{{- if not $namespaces -}}true{{- else if and (not (has "*" $namespaces)) (has $releaseNamespace $namespaces) -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
ClusterRole name used when watching ClusterProfiles in all namespaces.
*/}}
{{- define "argocd-clusterprofile-controller.clusterProfileClusterRoleName" -}}
{{- printf "%s-clusterprofiles" (include "argocd-clusterprofile-controller.controller.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ClusterProfile permissions required by the controller.
*/}}
{{- define "argocd-clusterprofile-controller.clusterProfileRules" -}}
- apiGroups:
    - multicluster.x-k8s.io
  resources:
    - clusterprofiles
  verbs:
    - get
    - list
    - patch
    - update
    - watch
{{- end }}

{{/*
Release-namespace permissions required by the controller.
*/}}
{{- define "argocd-clusterprofile-controller.localRules" -}}
- apiGroups:
    - ""
  resources:
    - secrets
  verbs:
    - create
    - delete
    - get
    - list
    - patch
    - update
    - watch
{{- if .Values.controller.enableLeaderElection }}
- apiGroups:
    - coordination.k8s.io
  resources:
    - leases
  verbs:
    - create
- apiGroups:
    - coordination.k8s.io
  resources:
    - leases
  resourceNames:
    - clusterprofile.argoproj.io
  verbs:
    - get
    - update
    - create
{{- end }}
{{- end }}
