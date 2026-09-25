{{- define "slotwise.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "slotwise.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "slotwise.selector" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "slotwise.image" -}}
{{- if not .Values.image.tag }}{{ fail "image.tag is required (git SHA)" }}{{ end -}}
{{ printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end -}}

{{- define "slotwise.secretName" -}}
{{- default (printf "%s-env" (include "slotwise.fullname" .)) .Values.secrets.existingSecret -}}
{{- end -}}

{{/* env from ConfigMap + Secret, identical for every workload */}}
{{- define "slotwise.envFrom" -}}
- configMapRef:
    name: {{ include "slotwise.fullname" . }}-config
- secretRef:
    name: {{ include "slotwise.secretName" . }}
{{- end -}}

{{/* read-only root FS needs a writable /tmp */}}
{{- define "slotwise.tmpVolume" -}}
- name: tmp
  emptyDir:
    sizeLimit: 128Mi
{{- end -}}
