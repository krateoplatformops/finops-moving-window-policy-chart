# Policy Bundle Deployment
This Helm chart is part of the [krateo-v2-template-finops-example-pricing-vm-azure](https://github.com/krateoplatformops/krateo-v2-template-finops-example-pricing-vm-azure) FinOps composition definition. It implements the policies required to configure Open Policy Agent. One of the policies is responbile for calling the [finops-moving-window-microservice](https://github.com/krateoplatformops/finops-moving-window-microservice), which allows for the optimization of Virtual Machines through the moving window algorithm.

## How to use this repository
All the policies contained in the `policies` folder can be compiled into the Helm Chart template configmap through the command:
```
make create
```

There are three policies by default:
- The router policy `main_router.rego`: this policy calls the correct policy depending on the apiVersion and Kind of the request object, it can be configured for new apiVersions and Kinds, for example for a Configmap kind that calls the `configmap_policy`:
  ```
  result := data.configmap_policy if {
  print("Evaluating request for ", .metadata.name, .apiVersion, .kind)
  .apiVersion  == "v1"
  .kind        == "Configmap"
  }
  ```
- The optimization policy `moving_window.rego`: it calls the [finops-moving-window-microservice](https://github.com/krateoplatformops/finops-moving-window-microservice) to compute the unused resources of a virtual machine: it requires the values of the composition to have the following fields:
  - `.spec.policyAdditionalValues.optimizationServiceEndpointRef.name`: The name of the microservice secret endpoint
  - `.spec.policyAdditionalValues.optimizationServiceEndpointRef.namespace`: The namespace of the microservice secret endpoint
  - `.spec.metricExporter.scraperDatabaseConfigRef.name`: The name of the database configuration for the scrapers
  - `.spec.metricExporter.scraperDatabaseConfigRef.namespace`: the namespace of the database configuration for the scrapers
  - `.spec.global.tableName`: the name of the table that contains the usage metrics of the target resource
- The helper `api_client.rego`: this file contains the functions that allow OPA to obtain live objects directly from the cluster (no caches or copies, like kube-mgmt sidecar). If you want to add your custom resources you will need to add the Kind of the custom resource with its apiVersion to `resource_group_mapping` variables

If you do add new resources to the policies, remember to update the RBAC as well and also restart the OPA pod to allow it to reload the policies.

## Usage
Mount the OCI bundle in the [OPA Helm Chart](https://github.com/krateoplatformops/opa-chart) with:
```yaml
opa:
  config:
    services:
      ghcr-registry:
        url: "https://ghcr.io/"
        type: oci
    bundles:
      authz:
        service: ghcr-registry
        resource: "ghcr.io/krateoplatformops/finops-moving-window-policy-chart:latest"
        persist: false
        polling:
          min_delay_seconds: 60
          max_delay_seconds: 120
```
