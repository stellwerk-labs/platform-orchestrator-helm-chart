{{- define "backend-module.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "backend-module.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "backend-module.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "backend-module.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "backend-module.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend-module.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Whether an enabled configuration profile reads the cluster's ServiceAccount
issuer discovery documents (OIDC configuration and JWKS) with the pod's own
ServiceAccount token. Renders "true" or nothing.
*/}}
{{- define "backend-module.serviceAccountIssuerDiscovery" -}}
{{- range $profile := .Values.configurationProfiles }}
{{- if and $profile.enabled $profile.serviceAccountIssuerDiscovery }}true{{ end }}
{{- end }}
{{- end }}
