{{- define "rag.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "rag.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "rag.selector" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "rag.image" -}}
{{- if not .Values.image.tag }}{{ fail "image.tag is required (git SHA)" }}{{ end -}}
{{ printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end -}}

{{- define "rag.secretName" -}}
{{- default (printf "%s-env" (include "rag.fullname" .)) .Values.secrets.existingSecret -}}
{{- end -}}

{{- define "rag.pod" -}}
serviceAccountName: {{ include "rag.fullname" .root }}
automountServiceAccountToken: false
securityContext: {{- toYaml .root.Values.podSecurityContext | nindent 2 }}
{{- with .root.Values.imagePullSecrets }}
imagePullSecrets: {{- toYaml . | nindent 2 }}
{{- end }}
volumes:
  - name: tmp
    emptyDir: { sizeLimit: 256Mi }
  - name: uploads
    persistentVolumeClaim:
      claimName: {{ include "rag.fullname" .root }}-uploads
{{- end -}}

{{- define "rag.container" -}}
image: {{ include "rag.image" .root }}
imagePullPolicy: {{ .root.Values.image.pullPolicy }}
envFrom:
  - configMapRef: { name: {{ include "rag.fullname" .root }}-config }
  - secretRef: { name: {{ include "rag.secretName" .root }} }
securityContext: {{- toYaml .root.Values.containerSecurityContext | nindent 2 }}
volumeMounts:
  - { name: tmp, mountPath: /tmp }
  - { name: uploads, mountPath: /app/data/uploads }
{{- end -}}
