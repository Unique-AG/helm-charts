{{/*
SPDX-SnippetBegin
SPDX-License-Identifier: Apache License 2.0
SPDX-SnippetCopyrightText: Copyright Broadcom, Inc.
SPDX-SnippetCopyrightText: 2024 © Unique AG
SPDX-SnippetEnd
*/}}

{{/* vim: set filetype=mustache: */}}

{{/*
Return a resource request/limit object based on a given preset.
These presets are for basic testing and not meant to be used in production
{{ include "resources.preset" (dict "type" "yocto") -}}
*/}}
{{- define "resources.preset" -}}
{{/* The limits are the requests increased by 50% (except ephemeral-storage and xlarge/2xlarge sizes)*/}}
{{- $presets := dict 
  "yocto" (dict 
      "requests" (dict "cpu" "2m" "memory" "4Mi" "ephemeral-storage" "10Mi")
      "limits" (dict "cpu" "4m" "memory" "8Mi" "ephemeral-storage" "20Mi")
   )
  "zepto" (dict 
      "requests" (dict "cpu" "4m" "memory" "8Mi" "ephemeral-storage" "20Mi")
      "limits" (dict "cpu" "8m" "memory" "16Mi" "ephemeral-storage" "40Mi")
   )
  "atto" (dict 
      "requests" (dict "cpu" "8m" "memory" "16Mi" "ephemeral-storage" "40Mi")
      "limits" (dict "cpu" "16m" "memory" "32Mi" "ephemeral-storage" "80Mi")
   )
 }}
{{- if hasKey $presets .type -}}
{{- index $presets .type | toYaml -}}
{{- else -}}
{{- printf "ERROR: Preset key '%s' invalid. Allowed values are %s" .type (join "," (keys $presets)) | fail -}}
{{- end -}}
{{- end -}}