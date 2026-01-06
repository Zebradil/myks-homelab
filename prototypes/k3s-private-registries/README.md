# K3s Private Registries Prototype

This prototype configures K3s nodes to use private Docker registries by creating a DaemonSet that writes the `/etc/rancher/k3s/registries.yaml` file on each node.

## Features

- Accepts K3s registries configuration as-is (no processing or transformation)
- Supports all K3s registry features: mirrors, authentication, TLS, rewrites
- Uses SOPS encrypted secrets for credentials via `sops()` functions
- Shows configuration diffs with masked secrets for security
- Automatically restarts when configuration changes
- Runs on all nodes with appropriate tolerations
- Resource-efficient: containers exit after completion
- Secure: Uses Kubernetes Secret instead of ConfigMap for sensitive registry data

## Configuration

The prototype accepts a standard K3s `registries.yaml` configuration. You can use any structure documented in the [K3s Private Registry Documentation](https://docs.k3s.io/installation/private-registry).

### Basic Registry Mirrors

```yaml
application:
  registries:
    mirrors:
      docker.io:
        endpoint:
          - "https://registry.example.com:5000"
      registry.example.com:
        endpoint:
          - "https://registry.example.com:5000"
        rewrite:
          "^rancher/(.*)": "mirrorproject/rancher-images/$1"
```

### Registry with Authentication

You can reference encrypted secrets directly in your configuration using `sops()` functions:

```yaml
#@ load("secrets.star", "sops")

application:
  registries:
    mirrors:
      docker.io:
        endpoint:
          - "https://registry.example.com:5000"
    configs:
      "registry.example.com:5000":
        auth:
          username: #@ sops("0", "my_registry_username")
          password: #@ sops("0", "my_registry_password")
      docker.io:
        auth:
          username: my_dockerhub_user
          password: #@ sops("0", "dockerhub_token")
```

### TLS Configuration

```yaml
application:
  registries:
    configs:
      "registry.example.com:5000":
        tls:
          ca_file: "/etc/ssl/certs/ca.pem"
          cert_file: "/etc/ssl/certs/client.pem"
          key_file: "/etc/ssl/certs/client-key.pem"
          insecure_skip_verify: false
```

### Complete Example

```yaml
#@ load("secrets.star", "sops")

application:
  registries:
    mirrors:
      docker.io:
        endpoint:
          - "https://registry.example.com:5000"
      "*.gcr.io":
        endpoint:
          - "https://gcr-mirror.example.com"
        rewrite:
          "^(.*)": "mirror-project/$1"
    configs:
      "registry.example.com:5000":
        auth:
          username: #@ sops("0", "private_registry_user")
          password: #@ sops("0", "private_registry_pass")
        tls:
          insecure_skip_verify: true
      "gcr-mirror.example.com":
        auth:
          token: #@ sops("0", "gcr_access_token")
        tls:
          ca_file: "/etc/ssl/certs/gcr-ca.pem"
```

### Wildcard Support

K3s supports wildcard configurations for default settings:

```yaml
application:
  registries:
    mirrors:
      "*":
        endpoint:
          - "https://registry.example.com:5000"
    configs:
      "*":
        tls:
          insecure_skip_verify: true
      "docker.io": {}  # Override wildcard for docker.io
```

## How it Works

1. **Secret**: Contains the exact `registries.yaml` content you provide (stored securely as a Kubernetes Secret)
2. **DaemonSet**: Runs on all nodes with an init container that:
   - Creates the `/etc/rancher/k3s` directory if needed
   - Compares old vs new configuration and shows diff (with secrets masked)
   - Writes the new `registries.yaml` file to the host
   - Exits after completion (resource-efficient)
3. **Pause Container**: Minimal container that keeps the pod running with minimal resource usage
4. **Secret Masking**: Uses `yq` to safely mask `auth.username`, `auth.password`, and `auth.token` in diff output
5. **Restart Detection**: Uses checksum annotations to restart pods when configuration changes

## Example Log Output

### When updating existing configuration:
```bash
Comparing old and new configurations...
--- OLD /etc/rancher/k3s/registries.yaml
+++ NEW /etc/rancher/k3s/registries.yaml
@@ -3,7 +3,7 @@
     docker.io:
       endpoint:
-        - "https://old-registry.com"
+        - "https://new-registry.com"
   configs:
     docker.io:
       auth:
         username: <REDACTED>
         password: <REDACTED>
Configuration changes detected (secrets redacted in diff above)
```

### When creating new configuration:
```bash
Creating new registries configuration file
New configuration preview (secrets redacted):
  mirrors:
    docker.io:
      endpoint:
        - "https://registry.example.com"
  configs:
    docker.io:
      auth:
        username: <REDACTED>
        password: <REDACTED>
```

## Post-Deployment

After deploying this prototype:

1. **Monitor the logs**: Check that configuration was applied successfully:
   ```bash
   kubectl logs -l app=<your-app-name>-writer
   ```

2. **Restart K3s**: The registries configuration only takes effect after restarting K3s on each node:
   ```bash
   sudo systemctl restart k3s
   # or for k3s agent nodes:
   sudo systemctl restart k3s-agent
   ```

3. **Verify Configuration**: Check that the file was written correctly:
   ```bash
   cat /etc/rancher/k3s/registries.yaml
   ```

4. **Test Registry Access**: Try pulling an image from your private registry:
   ```bash
   sudo k3s crictl pull registry.example.com:5000/my-image:latest
   ```

## Troubleshooting

- **Check DaemonSet status**: `kubectl get ds <your-app-name>-writer`
- **View logs**: `kubectl logs -l app=<your-app-name>-writer`
- **Check Secret**: `kubectl get secret <your-app-name>-config -o yaml`
- **Verify file on host**: `ls -la /etc/rancher/k3s/`
- **K3s containerd logs**: `sudo journalctl -u k3s -f`

## Security Features

- **Kubernetes Secret**: Registry configuration stored as Secret instead of ConfigMap for better security
- **Secret Masking**: All `username`, `password`, and `token` values are masked as `<REDACTED>` in logs
- **YAML-aware Processing**: Uses `yq` for reliable secret detection and masking
- **Minimal Privileges**: Runs as root only for filesystem access, no unnecessary capabilities
- **Temporary Files**: Masked diff files are automatically cleaned up

## References

- [K3s Private Registry Documentation](https://docs.k3s.io/installation/private-registry)
- [Containerd Registry Configuration](https://github.com/containerd/containerd/blob/main/docs/cri/registry.md)
- [yq YAML Processor](https://mikefarah.gitbook.io/yq/) 
