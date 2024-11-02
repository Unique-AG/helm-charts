{{- define "renderArray" -}}
array:
  {{- range . }}
  - |
    objectName: {{ .kvObjectName }}
    objectType: secret
  {{- end }}
{{- end -}}

{{- define "renderData" -}}
data:
  {{- range . }}
  - key: {{ .k8sSecretDataKey }}
    objectName: {{ .kvObjectName }}
  {{- end -}}
{{- end -}}
