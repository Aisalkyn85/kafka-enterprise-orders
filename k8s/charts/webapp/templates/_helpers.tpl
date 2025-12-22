{{- define "ghcr.dockerconfigjson" -}}
{{- $auth := printf "%s:%s" .Values.ghcr.username .Values.ghcr.password | b64enc -}}
{{- $dockerConfig := dict "auths" (dict "ghcr.io" (dict "username" .Values.ghcr.username "password" .Values.ghcr.password "auth" $auth)) -}}
{{ $dockerConfig | toJson | b64enc }}
{{- end -}}
