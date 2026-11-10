{{define "signature_func" -}}
```mojo
{{if .Signature}}{{.Signature}}{{else}}def {{.Name}}{{end}}
```
{{- end}}
