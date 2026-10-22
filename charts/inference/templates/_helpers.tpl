{{- define "inference.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride }}
{{- else }}
inference
{{- end }}
{{- end }}

{{- define "inference.selectorLabels" -}}
app.kubernetes.io/name: inference
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "inference.labels" -}}
{{ include "inference.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: k8s-ml-platform
app.kubernetes.io/component: inference
{{- end }}

{{- define "inference.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
capabilities:
  drop:
    - ALL
seccompProfile:
  type: RuntimeDefault
{{- end }}
