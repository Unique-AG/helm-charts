{{/*
Expand the name of the chart.
*/}}
{{- define "agent-sandbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "agent-sandbox.fullname" -}}
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
{{- define "agent-sandbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "agent-sandbox.labels" -}}
helm.sh/chart: {{ include "agent-sandbox.chart" . }}
{{ include "agent-sandbox.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "agent-sandbox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agent-sandbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Controller labels
*/}}
{{- define "agent-sandbox.controller.labels" -}}
{{ include "agent-sandbox.labels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{/*
Controller selector labels
*/}}
{{- define "agent-sandbox.controller.selectorLabels" -}}
{{ include "agent-sandbox.selectorLabels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{/*
Controller image
*/}}
{{- define "agent-sandbox.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}{{ if .Values.image.digest }}@{{ .Values.image.digest }}{{ end }}
{{- end }}

{{/*
Controller args
*/}}
{{- define "agent-sandbox.args" -}}
{{- if .Values.leaderElect }}
- "--leader-elect=true"
{{- end }}
{{- if .Values.extensions.enabled }}
- "--extensions"
{{- end }}
{{- end }}

{{/*
Router name
*/}}
{{- define "agent-sandbox.router.name" -}}
{{- printf "%s-router" (include "agent-sandbox.fullname" .) }}
{{- end }}

{{/*
Router labels
*/}}
{{- define "agent-sandbox.router.labels" -}}
{{ include "agent-sandbox.labels" . }}
app.kubernetes.io/component: router
{{- end }}

{{/*
Router selector labels
*/}}
{{- define "agent-sandbox.router.selectorLabels" -}}
{{ include "agent-sandbox.selectorLabels" . }}
app.kubernetes.io/component: router
app: sandbox-router
{{- end }}
