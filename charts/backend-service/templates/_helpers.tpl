{{- define "backendService.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "backendService.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Release.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "backendService.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "backendService.serviceAccountName" -}}
{{- if .Values.serviceAccount.enabled }}
{{- default (include "backendService.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "backendService.clusterInternalServiceSuffix" -}}
{{- $clusterInternalServiceSuffix := default ".svc.cluster.local" .Values.clusterInternalServiceSuffix }}
{{- if not (hasPrefix "." $clusterInternalServiceSuffix) }}
{{- fail "clusterInternalServiceSuffix must start with a dot!" }}
{{- end }}
{{- printf "%s" $clusterInternalServiceSuffix }}
{{- end }}

{{/* 🚨 ‼️ Changing the immutableLabels will lead to downtime when deploying as selector labels can only be updated manually or with downtime ‼️ 🚨 */}}
{{/* These labels never change and are also used as matchLabels for selectors */}}
{{- define "backendService.immutableLabels" -}}
app.kubernetes.io/name: {{ include "backendService.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* 🚨 ‼️ Changing the selectorLabels will lead to downtime when deploying as selector labels can only be updated manually or with downtime ‼️ 🚨 */}}
{{- define "backendService.selectorLabels" -}}
{{- include "backendService.immutableLabels" . }}
app.kubernetes.io/component: server
{{- end }}

{{- define "backendService.serviceLabels" -}}
{{- include "backendService.labels" . }}
{{ with .Values.service.extraLabels }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/* These labels are shared between all components (or shared resources) and have no component awareness */}}
{{- define "backendService.mutableLabels" -}}
{{- include "backendService.immutableLabels" . }}
{{- end }}

{{/* These labels identify all resources that belong to our main deployment, called "server" */}}
{{- define "backendService.labels" -}}
{{- include "backendService.mutableLabels" . }}
{{- end }}

{{/* These labels identify cronjob specific resources */}}
{{- define "backendService.labelsCronJob" -}}
{{- include "backendService.mutableLabels" . }}
app.kubernetes.io/component: cron-job
{{- end }}

{{/* These labels identify db migration job specific resources */}}
{{- define "backendService.labelsHooks" -}}
{{- include "backendService.mutableLabels" . }}
app.kubernetes.io/component: hook
{{- end }}

{{/* Helper to get the prefix */}}
{{- define "backendService.routePrefix" -}}
{{- if .Values.routes.pathPrefix -}}
{{- .Values.routes.pathPrefix -}}
{{- else -}}
/{{- include "backendService.fullname" . -}}
{{- end -}}
{{- end -}}

{{/* Helper to get the service port */}}
{{- define "backendService.servicePort" -}}
{{- if .Values.service.port -}}
{{- .Values.service.port -}}
{{- else if .Values.ports.service -}}
{{- .Values.ports.service -}}
{{- else -}}
80
{{- end -}}
{{- end -}}

{{/* Helper to get the application port */}}
{{- define "backendService.applicationPort" -}}
{{- if .Values.ports.application -}}
{{- .Values.ports.application -}}
{{- else -}}
8080
{{- end -}}
{{- end -}}

{{/* Helper to get the image tag - uses image.tag if specified, otherwise falls back to Chart.AppVersion */}}
{{- define "backendService.imageTag" -}}
{{- if .Values.image.tag -}}
{{- .Values.image.tag -}}
{{- else -}}
{{- .Chart.AppVersion -}}
{{- end -}}
{{- end -}}

{{/* Validate GCP workload identity configuration */}}
{{- define "backendService.validateGcpWorkloadIdentity" -}}
{{- if .Values.workloadIdentity.gcp.enabled -}}
{{- if not .Values.workloadIdentity.gcp.projectId -}}
{{- fail "workloadIdentity.gcp.projectId is required when workloadIdentity.gcp.enabled is true" -}}
{{- end -}}
{{- if not .Values.workloadIdentity.gcp.workloadIdentityPool -}}
{{- fail "workloadIdentity.gcp.workloadIdentityPool is required when workloadIdentity.gcp.enabled is true" -}}
{{- end -}}
{{- if not .Values.workloadIdentity.gcp.provider -}}
{{- fail "workloadIdentity.gcp.provider is required when workloadIdentity.gcp.enabled is true" -}}
{{- end -}}
{{- if not .Values.workloadIdentity.gcp.serviceAccountEmail -}}
{{- fail "workloadIdentity.gcp.serviceAccountEmail is required when workloadIdentity.gcp.enabled is true" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Helper to render route timeouts (GEP-2257) */}}
{{/* Expects dict with pathConfig (per-path config) and globalConfig (routes config) */}}
{{/* Priority: pathConfig.timeouts > pathConfig.timeout > globalConfig.timeouts > globalConfig.timeout */}}
{{- define "backendService.routeTimeouts" -}}
{{- $pathConfig := .pathConfig -}}
{{- $globalConfig := .globalConfig -}}
{{- if or $pathConfig.timeout $pathConfig.timeouts $globalConfig.timeout $globalConfig.timeouts -}}
timeouts:
{{- if $pathConfig.timeouts }}
  {{- toYaml $pathConfig.timeouts | nindent 2 }}
{{- else if $pathConfig.timeout }}
  request: {{ $pathConfig.timeout | quote }}
  backendRequest: {{ $pathConfig.timeout | quote }}
{{- else if $globalConfig.timeouts }}
  {{- toYaml $globalConfig.timeouts | nindent 2 }}
{{- else if $globalConfig.timeout }}
  request: {{ $globalConfig.timeout | quote }}
  backendRequest: {{ $globalConfig.timeout | quote }}
{{- end }}
{{- end -}}
{{- end -}}
