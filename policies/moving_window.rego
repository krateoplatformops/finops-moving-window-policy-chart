package finops_admission

import data.kubernetes.api.client
import rego.v1

operations := {"UPDATE"}

default apiVersion = "admission.k8s.io/v1beta1"
apiVersion = input.apiVersion
default response_uid = ""
response_uid := input.request.uid

main := msg if {
    print("Evaluating moving window policy")
    operations[input.request.operation]
    print("Operation: UPDATE")
    patches := [{
        "op": "add", 
        "path": "/spec/optimization", 
        "value": sprintf("%s", optimization_data)
    }]
    fullPatches := ensureParentPathsExist(patches)

    response := {
        "allowed": true,
        "patchType": "JSONPatch",
        "uid": response_uid,
        "patch": base64.encode(json.marshal(fullPatches))
    }

    msg = {
        "apiVersion": apiVersion,
        "kind": "AdmissionReview",
        "response": response,
    }
}


optimization_data := result if {
    optimizationServiceSecretName := input.request.object.spec.policyAdditionalValues.optimizationServiceEndpointRef.name
    optimizationServiceSecretNamespace := input.request.object.spec.policyAdditionalValues.optimizationServiceEndpointRef.namespace
    print("Got secret data for optimization service: ", optimizationServiceSecretName, optimizationServiceSecretNamespace)
    databaseHandlerSecretName := concat("-", [input.request.object.spec.metricExporter.scraperDatabaseConfigRef.name, "endpoint"])
    databaseHandlerSecretNamespace := input.request.object.spec.metricExporter.scraperDatabaseConfigRef.namespace
    print("Got secret data for database handler: ", databaseHandlerSecretName, databaseHandlerSecretNamespace)
    table_name := concat("_", [input.request.object.spec.global.tableName, "res"])
    print("Table name is: ", table_name)
    objService := client.query_name_ns("secrets", optimizationServiceSecretName, optimizationServiceSecretNamespace)
    optimizationServiceEndpoint := objService.body
    print("Got response to GET secret optimizationService: ", objService.status)
    objDBHandler := client.query_name_ns("secrets", databaseHandlerSecretName, databaseHandlerSecretNamespace)
    databaseHandlerEndpoint := objDBHandler.body
    print("Got response to GET secret dbHandler: ", objDBHandler.status)
    databaseHandlerUrl := base64.decode(databaseHandlerEndpoint.data["server-url"])
    optimizationServiceUrl := base64.decode(optimizationServiceEndpoint.data["server-url"])
    username := base64.decode(databaseHandlerEndpoint.data["username"])
    password := base64.decode(databaseHandlerEndpoint.data["password"])
    print("Secret values: ", databaseHandlerUrl, optimizationServiceUrl, username, password)
    vm_resource_ids := get_vm_resource_ids
    print("VM resources found:", vm_resource_ids)
    result := query_external_service(optimizationServiceUrl, databaseHandlerUrl, username, password, table_name, vm_resource_ids)
}

get_vm_resource_ids := resource_ids if {
    print("Getting live object...")
    live := client.query_name_ns("vmazures", input.request.object.metadata.name, input.request.object.metadata.namespace)
    print("Got response to GET live object: ", live.status)
    live.status_code == 200
    print("Got live object")
    managed_resources := live.body.status.managed
    vm_resources := [res | res := managed_resources[_]; res.resource == "virtualmachines"]
    vm_objects := [client.query_name_ns("virtualmachines", res.name, res.namespace) | res := vm_resources[_]]
    resource_ids := [vm.body.status.id | vm := vm_objects[_]]
}

query_external_service(optimizationServiceUrl, databaseHandlerUrl, username, password, table_name, resource_ids) := responses if {
    responses := [query_single_resource(optimizationServiceUrl, databaseHandlerUrl, username, password, table_name, resource_id) | resource_id := resource_ids[_]]
}

query_single_resource(optimizationServiceUrl, databaseHandlerUrl, username, password, table_name, resource_id) := response if {
    url := sprintf("%s/optimize?resource_name=%s&table_name=%s&dbhandler_url=%s/compute", [optimizationServiceUrl, resource_id, table_name, databaseHandlerUrl])
    auth_header := sprintf("Basic %s", [base64.encode(sprintf("%s:%s", [username, password]))])
    print("microservice compute url: ", url)
    http_response := http.send({
        "method": "GET",
        "url": url,
        "headers": {
            "Authorization": auth_header,
            "Accept": "application/json"
        },
        "raise_error": true
    })
    
    http_response.status_code == 200
    print("microservice response: ", http_response)
    response := http_response.body
}

###########################################################################
# Ensure parent paths exist
###########################################################################

ensureParentPathsExist(patches) = result if {
    # Convert patches to a set
    paths := {p.path | p := patches[_]}
    # Compute all missing subpaths.
    missingPaths := {sprintf("/%s", [concat("/", prefixPath)]) |
        paths[path]
        pathArray := split(path, "/")
        pathArray[i] # walk over path
        i > 0 # skip initial element
        # array of all elements in path up to i
        prefixPath := [pathArray[j] | pathArray[j]; j < i; j > 0] # j > 0: skip initial element
        walkPath := [toWalkElement(x) | x := prefixPath[_]]
        not inputPathExists(walkPath) with input as input.request.object
    }
    # Sort paths, to ensure they apply in correct order
    ordered_paths := sort(missingPaths)
    # Return new patches prepended to original patches.
    new_patches := [{"op": "add", "path": p, "value": {}} |
        p := ordered_paths[_]
    ]
    result := array.concat(new_patches, patches)
}

###########################################################################
# Check that the given @path exists as part of the input object
###########################################################################

inputPathExists(path) if {
    walk(input, [path, _])
}

toWalkElement(str) = str if {
    not regex.match("^[0-9]+$", str)
}

toWalkElement(str) = x if {
    regex.match("^[0-9]+$", str)
    x := to_number(str)
}