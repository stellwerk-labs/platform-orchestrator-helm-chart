{{- define "seaweed.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "seaweed.fullname" -}}
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

{{- define "seaweed.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "seaweed.labels" -}}
helm.sh/chart: {{ include "seaweed.chart" . }}
{{ include "seaweed.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "seaweed.selectorLabels" -}}
app.kubernetes.io/name: {{ include "seaweed.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "seaweedfs.s3.fullname" -}}
{{- printf "%s-s3" (include "seaweed.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "seaweedfs.s3.serviceEndpoint" -}}
{{- printf "http://%s-filer.%s.svc.cluster.local:8333/"  (include "seaweed.fullname" .) .Release.Namespace -}}
{{- end -}}