{{/*
Expand the name of the chart.
*/}}
{{- define "postgres-vdb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "postgres-vdb.fullname" -}}
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
{{- define "postgres-vdb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "postgres-vdb.labels" -}}
helm.sh/chart: {{ include "postgres-vdb.chart" . }}
{{ include "postgres-vdb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: postgres-vdb-platform
{{- end }}

{{/*
Selector labels
*/}}
{{- define "postgres-vdb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres-vdb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "postgres-vdb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "postgres-vdb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate database connection string
*/}}
{{- define "postgres-vdb.connectionString" -}}
{{- printf "postgresql://%s:%s@%s:%d/%s" .Values.vdb.database.user .Values.vdb.database.password .Release.Name (.Values.vdb.port | int) .Values.vdb.database.name }}
{{- end }}

{{/*
Generate JDBC URL
*/}}
{{- define "postgres-vdb.jdbcUrl" -}}
{{- printf "jdbc:postgresql://%s:%d/%s" .Release.Name (.Values.vdb.port | int) .Values.vdb.database.name }}
{{- end }}
