{{define "signature_struct" -}}
```mojo
{{if .Signature}}{{.Signature}}{{else}}struct {{.Name}}{{end}}
```
{{- end}}
