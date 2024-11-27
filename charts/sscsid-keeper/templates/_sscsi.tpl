{{- define "renderArray" -}}
array:
  {{- range . }}
  - |
    objectName: {{ .kvObjectName }}
    objectType: secret
  {{- end }}
{{- end -}}

{{- define "renderData" -}}
  {{- range . }}
  - key: {{ .k8sSecretDataKey }}
    objectName: {{ .kvObjectName }}
  {{- end -}}
{{- end -}}
