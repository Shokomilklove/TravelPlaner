{{/* Chart name */}}
{{- define "tp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels */}}
{{- define "tp.labels" -}}
app.kubernetes.io/name: {{ include "tp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* Build a full image reference for a given repository */}}
{{- define "tp.image" -}}
{{- $reg := .root.Values.image.registry -}}
{{- if $reg -}}
{{- printf "%s/%s:%s" $reg .repo (.root.Values.image.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .repo (.root.Values.image.tag | toString) -}}
{{- end -}}
{{- end -}}

{{/* Secret name: existing or chart-managed */}}
{{- define "tp.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
trip-service-secrets
{{- end -}}
{{- end -}}

{{/* Build DATABASE_URL for external PostgreSQL */}}
{{- define "tp.databaseUrl" -}}
{{- if .Values.postgres.enabled -}}
{{- printf "postgresql+psycopg2://%s:%s@postgres:5432/%s" .Values.postgres.user .Values.postgres.password .Values.postgres.database -}}
{{- else -}}
{{- printf "postgresql+psycopg2://%s:${POSTGRES_PASSWORD}@%s:%v/%s" .Values.postgres.user .Values.postgres.host .Values.postgres.port .Values.postgres.database -}}
{{- end -}}
{{- end -}}