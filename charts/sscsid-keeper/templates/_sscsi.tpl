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
  - key: APISecret
    objectName: {{ .kvObjectName }}
  {{- end -}}
{{- end -}}
