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
{{- $ingressEnabled := (.Values.ingress.enabled | default false) -}}
{{- $gatewayEnabled := (.Values.gateway.enabled | default false) -}}
{{- if and $ingressEnabled $gatewayEnabled -}}
{{- fail "Only one north-south routing mode can be enabled at a time: set either ingress.enabled=true or gateway.enabled=true, not both." -}}
{{- end -}}
{{- $gateway := (.Values.gateway | default (dict)) -}}
{{- $parentRefs := ($gateway.parentRefs | default (list)) -}}
{{- if and $gatewayEnabled (eq (len $parentRefs) 0) (empty ($gateway.name | default "")) -}}
{{- fail "gateway.name is required when gateway.enabled=true and gateway.parentRefs is empty" -}}
{{- end -}}
{{- if and $gatewayEnabled (gt (len $parentRefs) 0) -}}
{{- range $idx, $ref := $parentRefs -}}
{{- if empty ($ref.name | default "") -}}
{{- fail (printf "gateway.parentRefs[%d].name is required when gateway.enabled=true" $idx) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and $gatewayEnabled (empty ($gateway.host | default "")) -}}
{{- fail "gateway.host is required when gateway.enabled=true" -}}
{{- end -}}
{{- $pg := .Values.db.postgres | default (dict) -}}
{{- $sslMode := ($pg.sslMode | default "") -}}
{{- $pgRoot := ($pg.sslRootCert | default (dict)) -}}
{{- if and (or (eq $sslMode "verify-ca") (eq $sslMode "verify-full")) (not ($pgRoot.enabled | default false)) -}}
{{- fail "db.postgres.sslRootCert.enabled=true is required when db.postgres.sslMode is verify-ca or verify-full" -}}
{{- end -}}
{{- if and ($pgRoot.enabled | default false) (empty ($pgRoot.existingSecret | default "")) -}}
{{- fail "db.postgres.sslRootCert.existingSecret is required when db.postgres.sslRootCert.enabled=true" -}}
{{- end -}}
{{- $temporalTls := (.Values.temporal.tls | default (dict)) -}}
{{- $temporalCa := ($temporalTls.ca | default (dict)) -}}
{{- if and ($temporalTls.enabled | default false) (empty ($temporalCa.existingSecret | default "")) -}}
{{- fail "temporal.tls.ca.existingSecret is required when temporal.tls.enabled=true" -}}
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
{{- $tag := (get $images "tag") | default "1.6.0" -}}
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


{{/*
------------------------------------------------------------------------------
PostgreSQL root certificate path inside Espresso containers.
------------------------------------------------------------------------------
*/}}
{{- define "espresso.postgresSslRootCertPath" -}}
{{- $pg := .Values.db.postgres -}}
{{- $root := ($pg.sslRootCert | default (dict)) -}}
{{- $mountPath := ($root.mountPath | default "/etc/espresso/postgres-trust") -}}
{{- $fileName := ($root.fileName | default "ca.crt") -}}
{{- printf "%s/%s" (trimSuffix "/" $mountPath) $fileName -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Temporal CA certificate path inside Espresso containers.
------------------------------------------------------------------------------
*/}}
{{- define "espresso.temporalCaFile" -}}
{{- $tls := (.Values.temporal.tls | default (dict)) -}}
{{- $ca := ($tls.ca | default (dict)) -}}
{{- $mountPath := ($ca.mountPath | default "/etc/espresso/trust") -}}
{{- $fileName := ($ca.fileName | default "ca.crt") -}}
{{- printf "%s/%s" (trimSuffix "/" $mountPath) $fileName -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Temporal Frontend host used by Espresso clients.
If temporal.kubernetesNamespace is set and temporal.host is a short Service name,
render the Kubernetes cross-namespace DNS name: <service>.<namespace>.svc.
------------------------------------------------------------------------------
*/}}
{{- define "espresso.temporalHost" -}}
{{- $temporal := (.Values.temporal | default (dict)) -}}
{{- $host := ($temporal.host | default "temporal-frontend") -}}
{{- $namespace := ($temporal.kubernetesNamespace | default "") -}}
{{- if and $namespace (not (contains "." $host)) -}}
{{- printf "%s.%s.svc" $host $namespace -}}
{{- else -}}
{{- $host -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Temporal TLS server name. Defaults to the effective Temporal host when not explicitly set.
------------------------------------------------------------------------------
*/}}
{{- define "espresso.temporalTlsServerName" -}}
{{- $tls := (.Values.temporal.tls | default (dict)) -}}
{{- ($tls.serverName | default (include "espresso.temporalHost" .)) -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Optional CA volumeMounts for Espresso application containers.
Use inside a container at the same indentation level as env/envFrom:
  {{- include "espresso.trustVolumeMounts" . | nindent 10 }}
------------------------------------------------------------------------------
*/}}
{{- define "espresso.trustVolumeMounts" -}}
{{- $pg := .Values.db.postgres -}}
{{- $pgRoot := ($pg.sslRootCert | default (dict)) -}}
{{- $temporalTls := (.Values.temporal.tls | default (dict)) -}}
{{- $temporalCa := ($temporalTls.ca | default (dict)) -}}
{{- if or ($pgRoot.enabled | default false) ($temporalTls.enabled | default false) }}
volumeMounts:
{{- if ($pgRoot.enabled | default false) }}
  - name: postgres-ca
    mountPath: {{ include "espresso.postgresSslRootCertPath" . | quote }}
    subPath: {{ ($pgRoot.fileName | default "ca.crt") | quote }}
    readOnly: true
{{- end }}
{{- if ($temporalTls.enabled | default false) }}
  - name: temporal-ca
    mountPath: {{ include "espresso.temporalCaFile" . | quote }}
    subPath: {{ ($temporalCa.fileName | default "ca.crt") | quote }}
    readOnly: true
{{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Optional CA volumes for Espresso pods.
Use under spec.template.spec at indentation 6:
  {{- include "espresso.trustVolumes" . | nindent 6 }}
------------------------------------------------------------------------------
*/}}
{{- define "espresso.trustVolumes" -}}
{{- $pg := .Values.db.postgres -}}
{{- $pgRoot := ($pg.sslRootCert | default (dict)) -}}
{{- $temporalTls := (.Values.temporal.tls | default (dict)) -}}
{{- $temporalCa := ($temporalTls.ca | default (dict)) -}}
{{- if or ($pgRoot.enabled | default false) ($temporalTls.enabled | default false) }}
volumes:
{{- if ($pgRoot.enabled | default false) }}
  - name: postgres-ca
    secret:
      secretName: {{ required "db.postgres.sslRootCert.existingSecret is required when db.postgres.sslRootCert.enabled=true" $pgRoot.existingSecret | quote }}
      items:
        - key: {{ ($pgRoot.secretKey | default "ca.crt") | quote }}
          path: {{ ($pgRoot.fileName | default "ca.crt") | quote }}
{{- end }}
{{- if ($temporalTls.enabled | default false) }}
  - name: temporal-ca
    secret:
      secretName: {{ required "temporal.tls.ca.existingSecret is required when temporal.tls.enabled=true" $temporalCa.existingSecret | quote }}
      items:
        - key: {{ ($temporalCa.secretKey | default "ca.crt") | quote }}
          path: {{ ($temporalCa.fileName | default "ca.crt") | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Temporal CLI TLS env vars for admin-tools init container.
Use under env: at list indentation.
------------------------------------------------------------------------------
*/}}
{{- define "espresso.temporalCliTlsEnv" -}}
{{- if (.Values.temporal.tls.enabled | default false) }}
- name: TEMPORAL_TLS_CA
  value: {{ include "espresso.temporalCaFile" . | quote }}
- name: TEMPORAL_TLS_ENABLE_HOST_VERIFICATION
  value: "true"
- name: TEMPORAL_TLS_SERVER_NAME
  value: {{ include "espresso.temporalTlsServerName" . | quote }}
- name: TEMPORAL_CLI_TLS_CA
  value: {{ include "espresso.temporalCaFile" . | quote }}
- name: TEMPORAL_CLI_TLS_ENABLE_HOST_VERIFICATION
  value: "true"
- name: TEMPORAL_CLI_TLS_SERVER_NAME
  value: {{ include "espresso.temporalTlsServerName" . | quote }}
{{- end }}
{{- end -}}
