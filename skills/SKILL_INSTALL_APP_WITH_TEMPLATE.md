# Installing Applications in Dev-System using App-Template with Persistent Storage and VolSync

## Overview
This skill documents the process of installing applications in the dev-system namespace using the app-template Helm chart with persistent storage and VolSync backup capabilities.

## Prerequisites
- Understanding of Kubernetes, Helm, FluxCD, and Kustomize
- Knowledge of the app-template Helm chart structure
- Access to the cluster configuration repository

## Process Steps

### 1. Directory Structure Setup
Create the necessary directory structure for the application:
```
kubernetes/apps/dev-system/<app-name>/
├── ks.yaml                    # Kustomization for the application
└── app/
    ├── helmrelease.yaml       # HelmRelease definition
    ├── kustomization.yaml     # App-specific kustomization
    └── volsync.values.yaml    # VolSync configuration
```

### 2. Main Kustomization File
Create the primary Kustomization file that FluxCD will use to deploy the application:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app-name>
spec:
  dependsOn: []
  interval: 1h
  path: ./kubernetes/apps/dev-system/<app-name>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: dev-system
  wait: false
  components:
    - ../../../../components/volsync
```

### 3. Application Kustomization File
Create the app-specific kustomization file with VolSync integration:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
generatorOptions:
  disableNameSuffixHash: true
configMapGenerator:
  - name: <app-name>-volsync-values
    files:
      - values.yaml=volsync.values.yaml
resources:
  - ./helmrelease.yaml
```

### 4. VolSync Configuration
Create the VolSync values file to define backup/replication settings:

```yaml
volumes:
  - name: <app-name>
    capacity: <appropriate-size>Gi
```

### 5. HelmRelease Definition
Define the application using the app-template Helm chart:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app-name>
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: app-template
  values:
    controllers:
      <app-name>:
        containers:
          app:
            image:
              repository: <image-repository>
              tag: <image-tag>
            ports:
              - name: http
                containerPort: <port-number>
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: false
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 10m
                memory: 100Mi
              limits:
                memory: 500Mi
    service:
      app:
        controller: <app-name>
        ports:
          http:
            port: <port-number>
            targetPort: <port-number>
    route:
      app:
        enabled: true
        parentRefs:
          - name: envoy-internal
            namespace: network
        hostnames:
          - "{{ .Release.Name }}.${DOMAIN1}"
        rules:
          - backendRefs:
              - port: <port-number>
                name: <app-name>
    persistence:
      data:
        existingClaim: "{{ .Release.Name }}"
        globalMounts:
          - path: <mount-path>
```

### 6. Integration with Dev-System
Update the main dev-system kustomization to include the new application:

```yaml
resources:
  - ./namespace.yaml
  # ... other resources ...
  - ./<app-name>/ks.yaml  # Add this line
```

## Key Points

1. **VolSync Component**: Include `../../../../components/volsync` in the components section of the main Kustomization file to enable automatic backups.

2. **Persistent Storage**: Use `existingClaim: "{{ .Release.Name }}"` in the persistence section to dynamically create PVCs based on the Helm release name.

3. **App-Template Usage**: The bjw-s/helm-charts app-template provides consistent deployment patterns across all applications.

4. **HTTP Routing**: Applications are automatically exposed via HTTPRoute using the Envoy gateway.

5. **Resource Management**: Basic CPU/memory requests and limits prevent resource exhaustion.

## Security Considerations

- Container security contexts restrict privileges
- Network policies should be considered for inter-service communication
- Image pull secrets for private registries
- RBAC permissions if the app requires special access

## Customization Options

- Modify resource requests/limits based on application requirements
- Adjust ports as needed for different services
- Change image repositories and tags for specific versions
- Customize persistence paths based on application needs
- Add environment variables, secrets, or config maps as required