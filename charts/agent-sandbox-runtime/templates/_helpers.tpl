{{/*
Expand the name of the chart.
*/}}
{{- define "sandbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "sandbox.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "sandbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "sandbox.labels" -}}
helm.sh/chart: {{ include "sandbox.chart" . }}
{{ include "sandbox.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sandbox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sandbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Router name
*/}}
{{- define "sandbox.router.name" -}}
{{- printf "%s-router" (include "sandbox.fullname" .) }}
{{- end }}

{{/*
Router labels
*/}}
{{- define "sandbox.router.labels" -}}
{{ include "sandbox.labels" . }}
app.kubernetes.io/component: router
{{- end }}

{{/*
Router selector labels
*/}}
{{- define "sandbox.router.selectorLabels" -}}
{{ include "sandbox.selectorLabels" . }}
app.kubernetes.io/component: router
app: sandbox-router
{{- end }}

{{/*
Sandbox template name
*/}}
{{- define "sandbox.template.name" -}}
{{- .Values.sandboxTemplate.name | default "python-sandbox-template" }}
{{- end }}
