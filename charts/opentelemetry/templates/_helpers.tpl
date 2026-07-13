{{- define "opentelemetry.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "opentelemetry.fullname" -}}
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

{{- define "opentelemetry.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "opentelemetry.labels" -}}
helm.sh/chart: {{ include "opentelemetry.chart" . }}
{{ include "opentelemetry.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "opentelemetry.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opentelemetry.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "opentelemetry.collector.serviceEndpoint" -}}
{{- printf "http://%s-collector.%s.svc.cluster.local:4317" .Values.collector.name .Release.Namespace -}}
{{- end -}}

{{/*
Render the collector image string.
*/}}
{{- define "opentelemetry.collector.image" -}}
{{- printf "%s:%s" .Values.collector.image.repository .Values.collector.image.tag -}}
{{- end -}}
