{{/*
==============================================================================
Espresso Helm helpers
- Robust against missing/empty values (nil-safe)
- Supports customer image mirroring via .Values.images.espressoRepo
- Supports optional imagePullSecrets via .Values.images.imagePullSecrets
==============================================================================
*/}}

{{- define "espresso.name" -}}
espresso
{{- end }}

{{- define "espresso.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "espresso.name" .) -}}
{{- end }}

{{- define "espresso.labels" -}}
app.kubernetes.io/name: {{ include "espresso.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "espresso.selectorLabels" -}}
app.kubernetes.io/name: {{ include "espresso.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "espresso.validate" -}}
{{- $iface := (.Values.espresso.interface | default "") -}}
{{- if not (or (eq $iface "REST") (eq $iface "AZSB")) -}}
{{- fail (printf "espresso.interface must be REST or AZSB (got: %s)" $iface) -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Build image reference for all Espresso (vendor) images.

Usage:
  image: {{ include "espresso.espressodoImage" (dict "root" . "name" "espresso-ui-webapp") }}

Behavior:
- Base repo can be overridden by customer via .Values.images.espressoRepo
  Default: "espressodo"
  Example override: "myregistry.azurecr.io/espresso"
  Result: myregistry.azurecr.io/espresso/<name>:<tag>

- Tag can be overridden via .Values.images.tag
  Default: "1.5.1" (keep this in chart values.yaml as you prefer)
------------------------------------------------------------------------------
*/}}
{{- define "espresso.espressodoImage" -}}
{{- $root := .root -}}
{{- $images := ($root.Values.images | default (dict)) -}}
{{- $repo := (get $images "espressoRepo") | default "espressodo" -}}
{{- $repo = trimSuffix "/" $repo -}}
{{- $tag := (get $images "tag") | default "1.5.1" -}}
{{- printf "%s/%s:%s" $repo .name $tag -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Optional imagePullSecrets

Supports both formats:
1) List of names:
   images:
     imagePullSecrets:
       - mysecret

2) List of objects:
   images:
     imagePullSecrets:
       - name: mysecret

Emits nothing if unset/empty.
------------------------------------------------------------------------------
*/}}
{{- define "espresso.imagePullSecrets" -}}
{{- $images := (.Values.images | default (dict)) -}}
{{- $secrets := (get $images "imagePullSecrets") | default (list) -}}
{{- if gt (len $secrets) 0 -}}
imagePullSecrets:
{{- range $secrets }}
  - name: {{ .name | default . | quote }}
{{- end }}
{{- end -}}
{{- end -}}
