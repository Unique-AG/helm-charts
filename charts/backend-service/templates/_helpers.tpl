{{/*
Expand the name of the chart.
*/}}
{{- define "backend-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "backend-service.fullname" -}}
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
{{- define "backend-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "backend-service.labels" -}}
helm.sh/chart: {{ include "backend-service.chart" . }}
{{ include "backend-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "backend-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "backend-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.enabled }}
{{- default (include "backend-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- "default" }}
{{- end }}
{{- end }}

{{/*
Get the application port
*/}}
{{- define "backend-service.applicationPort" -}}
{{- .Values.ports.application | default 8080 }}
{{- end }}

{{/*
Get the service port
*/}}
{{- define "backend-service.servicePort" -}}
{{- .Values.ports.service | default 80 }}
{{- end }}

{{/*
Get the cluster internal service suffix
*/}}
{{- define "backend-service.clusterInternalServiceSuffix" -}}
{{- $suffix := .Values.clusterInternalServiceSuffix | default ".svc.cluster.local" }}
{{- if not (hasPrefix "." $suffix) }}
{{- fail "clusterInternalServiceSuffix must start with a dot!" }}
{{- end }}
{{- $suffix }}
{{- end }}

{{/*
Common environment variables from ConfigMap
*/}}
{{- define "backend-service.envFrom" -}}
{{- if .Values.env }}
- configMapRef:
    name: {{ include "backend-service.fullname" . }}-env
{{- end }}
{{- if .Values.envSecrets }}
- secretRef:
    name: {{ include "backend-service.fullname" . }}-secrets
{{- end }}
{{- range .Values.extraEnvConfigMaps }}
- configMapRef:
    name: {{ . }}
{{- end }}
{{- range .Values.extraEnvSecrets }}
- secretRef:
    name: {{ . }}
{{- end }}
{{- end }}

{{/*
Common volume mounts for secrets provider
*/}}
{{- define "backend-service.secretsProviderVolumeMounts" -}}
{{- if and .Values.secretsProvider.enabled (eq .Values.secretsProvider.provider "azure") }}
{{- range .Values.secretsProvider.azure.keyVaults }}
- name: secrets-store-{{ .name }}
  mountPath: /mnt/secrets-store/{{ .name }}
  readOnly: true
{{- end }}
{{- end }}
{{- end }}

{{/*
Common volumes for secrets provider
*/}}
{{- define "backend-service.secretsProviderVolumes" -}}
{{- if and .Values.secretsProvider.enabled (eq .Values.secretsProvider.provider "azure") }}
{{- range .Values.secretsProvider.azure.keyVaults }}
- name: secrets-store-{{ .name }}
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ include "backend-service.fullname" $ }}-{{ .name }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common environment variables from secrets provider
*/}}
{{- define "backend-service.secretsProviderEnv" -}}
{{- if and .Values.secretsProvider.enabled (eq .Values.secretsProvider.provider "azure") }}
{{- range .Values.secretsProvider.azure.keyVaults }}
{{- range .secrets }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "backend-service.fullname" $ }}-{{ $.name }}
      key: {{ .key }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Get route prefix for Gateway API routes
*/}}
{{- define "backend-service.routePrefix" -}}
{{- if .Values.routes.pathPrefix -}}
{{- .Values.routes.pathPrefix -}}
{{- else -}}
/{{ include "backend-service.fullname" . }}
{{- end -}}
{{- end }}

{{/*
Common pod template metadata
*/}}
{{- define "backend-service.podTemplateMetadata" -}}
metadata:
  annotations:
    {{- with .Values.podAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    checksum/env: {{ include (print .Template.BasePath "/configmap-env.yaml") . | sha256sum }}
    {{- if .Values.envSecrets }}
    checksum/secrets: {{ include (print .Template.BasePath "/secret-env.yaml") . | sha256sum }}
    {{- end }}
  labels:
    {{- include "backend-service.selectorLabels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if and .Values.secretsProvider.enabled (eq .Values.secretsProvider.provider "azure") .Values.secretsProvider.azure.workloadIdentity.enabled }}
    azure.workload.identity/use: "true"
    {{- end }}
{{- end }}

{{/*
Common container spec
*/}}
{{- define "backend-service.containerSpec" -}}
name: {{ include "backend-service.fullname" . }}
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
imagePullPolicy: {{ .Values.image.pullPolicy }}
ports:
  - name: http
    containerPort: {{ include "backend-service.applicationPort" . }}
    protocol: TCP
{{- if .Values.probes.enabled }}
{{- with .Values.probes.liveness }}
livenessProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.probes.readiness }}
readinessProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.probes.startup }}
startupProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- with .Values.resources }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.securityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if or .Values.env .Values.envSecrets .Values.extraEnvConfigMaps .Values.extraEnvSecrets }}
envFrom:
{{- include "backend-service.envFrom" . | nindent 2 }}
{{- end }}
{{- if or .Values.envVars (and .Values.secretsProvider.enabled (eq .Values.secretsProvider.provider "azure")) }}
env:
{{- with .Values.envVars }}
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- include "backend-service.secretsProviderEnv" . | nindent 2 }}
{{- end }}
volumeMounts:
{{- with .Values.volumeMounts }}
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .Values.auditVolume.enabled }}
  - name: audit
    mountPath: {{ .Values.auditVolume.mountPath }}
{{- end }}
{{- include "backend-service.secretsProviderVolumeMounts" . | nindent 2 }}
{{- end }}

{{/*
Common pod spec
*/}}
{{- define "backend-service.podSpec" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
serviceAccountName: {{ include "backend-service.serviceAccountName" . }}
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.initContainers }}
initContainers:
{{- range . }}
  - name: {{ .name }}
    image: {{ .image | default "busybox:1.28" }}
    {{- with .command }}
    command:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .volumeMounts }}
    volumeMounts:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
{{- end }}
containers:
  - {{- include "backend-service.containerSpec" . | nindent 4 }}
{{- with .Values.sidecars }}
{{- range . }}
  - {{- toYaml . | nindent 4 }}
{{- end }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.terminationGracePeriodSeconds }}
terminationGracePeriodSeconds: {{ . }}
{{- end }}
volumes:
{{- with .Values.volumes }}
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .Values.auditVolume.enabled }}
  - name: audit
    persistentVolumeClaim:
      claimName: {{ include "backend-service.fullname" . }}-audit
{{- end }}
{{- include "backend-service.secretsProviderVolumes" . | nindent 2 }}
{{- end }}
